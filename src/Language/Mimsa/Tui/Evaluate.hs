{-# LANGUAGE OverloadedStrings #-}

module Language.Mimsa.Tui.Evaluate
  ( getExpressionForBinding,
  )
where

import qualified Brick.Widgets.List as L
import qualified Data.Map as M
import Language.Mimsa.Actions (resolveStoreExpression)
import Language.Mimsa.Store
import Language.Mimsa.Types

evaluateStoreExprToInfo ::
  Store Annotation ->
  StoreExpression Annotation ->
  Maybe (MonoType, Expr Name Annotation)
evaluateStoreExprToInfo store' storeExpr =
  let source = "" -- no nice error messages
   in case resolveStoreExpression store' source storeExpr of
        Right (ResolvedExpression mt _ _ _ _) -> Just (mt, storeExpression storeExpr)
        _ -> Nothing

hush :: Either e a -> Maybe a
hush (Right a) = Just a
hush _ = Nothing

getExpressionForBinding ::
  Store Annotation ->
  ResolvedDeps Annotation ->
  L.List () Name ->
  Maybe (ExpressionInfo Annotation)
getExpressionForBinding store' (ResolvedDeps deps) l = do
  (_, name) <- L.listSelectedElement l
  (_, storeExpr') <- M.lookup name deps
  subDeps <- hush $ resolveDeps store' (storeBindings storeExpr')
  let toInfo (mt, expr) = ExpressionInfo mt expr name subDeps
  toInfo <$> evaluateStoreExprToInfo store' storeExpr'
