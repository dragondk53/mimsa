{-# LANGUAGE OverloadedStrings #-}

module Language.Mimsa.Actions.BindExpression (bindExpression) where

import Control.Monad.Except (liftEither)
import qualified Data.Map as M
import Data.Text (Text)
import qualified Language.Mimsa.Actions.Graph as Actions
import qualified Language.Mimsa.Actions.Helpers.CheckStoreExpression as Actions
import qualified Language.Mimsa.Actions.Helpers.UpdateTests as Actions
import qualified Language.Mimsa.Actions.Monad as Actions
import qualified Language.Mimsa.Actions.Shared as Actions
import Language.Mimsa.Printer
import Language.Mimsa.Project.Helpers
import Language.Mimsa.Store
import Language.Mimsa.Types.AST
import Language.Mimsa.Types.Identifiers
import Language.Mimsa.Types.Project
import Language.Mimsa.Types.ResolvedExpression
import Language.Mimsa.Types.Store

-- bind a new expression to the project, updating any tests
bindExpression ::
  Expr Name Annotation ->
  Name ->
  Text ->
  Actions.ActionM (ExprHash, Int, ResolvedExpression Annotation, [Graphviz])
bindExpression expr name input = do
  project <- Actions.getProject
  -- if there is an existing binding of this name, bring its deps into scope
  -- perhaps this should be more specific and actually take the previous
  -- exprHash as an argument instead of the name
  resolvedExpr <- case getExistingBinding name project of
    -- there is an existing one, use its deps when evaluating
    Just se ->
      let newSe = se {storeExpression = expr}
       in Actions.checkStoreExpression input project newSe
    -- no existing binding, resolve as usual
    Nothing ->
      liftEither $
        Actions.getTypecheckedStoreExpression input project expr
  let storeExpr = reStoreExpression resolvedExpr
  Actions.bindStoreExpression storeExpr name
  graphviz <- Actions.graphExpression storeExpr
  case lookupBindingName project name of
    Nothing -> do
      Actions.appendMessage
        ( "Bound " <> prettyPrint name <> "."
        )
      pure (getStoreExpressionHash storeExpr, 0, resolvedExpr, graphviz)
    Just oldExprHash ->
      do
        Actions.appendMessage
          ( "Updated binding of " <> prettyPrint name <> "."
          )
        let newExprHash = getStoreExpressionHash storeExpr
        (,,,) newExprHash
          <$> Actions.updateTests oldExprHash newExprHash
            <*> pure resolvedExpr
            <*> pure graphviz

getExistingBinding ::
  Name ->
  Project Annotation ->
  Maybe (StoreExpression Annotation)
getExistingBinding name prj =
  lookupBindingName prj name
    >>= \exprHash -> M.lookup exprHash (getStore $ prjStore prj)
