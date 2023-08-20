{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeApplications #-}

module Smol.Core.Modules.Check
  ( checkModule,
  )
where

import Control.Monad.Except
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import Smol.Core
import Smol.Core.Modules.FromParts
import Smol.Core.Modules.ResolveDeps
import Smol.Core.Modules.Typecheck
import Smol.Core.Modules.Types.DefIdentifier
import Smol.Core.Modules.Types.Module
import Smol.Core.Modules.Types.ModuleError
import Smol.Core.Modules.Types.ModuleItem
import Smol.Core.Modules.Types.TopLevelExpression
import Smol.Core.Typecheck.Typeclass
import Smol.Core.Typecheck.Typeclass.BuiltIns

-- this is the front door as such
checkModule ::
  (MonadError (ModuleError Annotation) m) =>
  T.Text ->
  [ModuleItem Annotation] ->
  m (Module ResolvedDep (Type ResolvedDep Annotation))
checkModule input moduleItems = do
  myModule <- moduleFromModuleParts moduleItems

  let classes = builtInClasses @Annotation <> (resolveTypeclass <$> moClasses myModule)
      typeclassMethods = S.fromList . M.elems . fmap tcFuncName $ classes

  (resolvedModule, deps) <-
    modifyError ErrorInResolveDeps (resolveModuleDeps typeclassMethods myModule)

  typedModule <- typecheckModule input resolvedModule deps

  passModuleDictionaries typedModule

passModuleDictionaries ::
  (MonadError (ModuleError Annotation) m) =>
  Module ResolvedDep (Type ResolvedDep Annotation) ->
  m (Module ResolvedDep (Type ResolvedDep Annotation))
passModuleDictionaries inputModule = do
  let env = envFromTypecheckedModule inputModule

  let passDictToTopLevelExpression (ident, tle) = do
        let constraints = constraintsFromTLE tle
            expr = tleExpr tle

        let thisEnv =
              env
                { tceConstraints = constraints
                }

        newExpr <-
          modifyError
            (DefDoesNotTypeCheck mempty (DIName ident))
            (toDictionaryPassing thisEnv constraints expr)

        pure (ident, tle {tleExpr = newExpr})

  newExpressions <- M.fromList <$> traverse passDictToTopLevelExpression (M.toList $ moExpressions inputModule)
  pure $ inputModule {moExpressions = newExpressions}
