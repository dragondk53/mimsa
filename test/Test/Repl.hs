{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Test.Repl
  ( spec,
  )
where

import qualified Data.Map as M
import Data.Text (Text)
import Language.Mimsa.Interpreter
import Language.Mimsa.Repl
import Language.Mimsa.Types
import Test.Helpers
import Test.Hspec

fstExpr :: StoreExpression
fstExpr = StoreExpression mempty expr'
  where
    expr' =
      MyLambda
        (mkName "tuple")
        ( MyLetPair
            (mkName "a")
            (mkName "b")
            (MyVar (mkName "tuple"))
            (MyVar (mkName "a"))
        )

isTenExpr :: StoreExpression
isTenExpr = StoreExpression mempty expr'
  where
    expr' =
      MyLambda
        (mkName "i")
        ( MyIf
            ( MyApp
                ( MyApp
                    (MyVar (mkName "eqInt"))
                    (MyVar (mkName "i"))
                )
                (int 10)
            )
            (MySum MyRight (MyVar (mkName "i")))
            (MySum MyLeft (MyVar (mkName ("i"))))
        )

eqTenExpr :: StoreExpression
eqTenExpr = StoreExpression mempty expr'
  where
    expr' =
      MyLambda
        (mkName "i")
        ( MyApp
            (MyApp (MyVar (mkName "eqInt")) (int 10))
            (MyVar (mkName "i"))
        )

fmapSum :: StoreExpression
fmapSum = StoreExpression mempty expr
  where
    expr =
      unsafeGetExpr
        "\\f -> \\a -> case a of Left (\\l -> Left l) | Right (\\r -> Right f(r))"

stdLib :: StoreEnv
stdLib = StoreEnv store' bindings'
  where
    store' =
      Store $
        M.fromList
          [ (ExprHash 1, fstExpr),
            (ExprHash 2, isTenExpr),
            (ExprHash 3, eqTenExpr),
            (ExprHash 4, fmapSum)
          ]
    bindings' =
      Bindings $
        M.fromList
          [ (mkName "fst", ExprHash 1),
            (mkName "isTen", ExprHash 2),
            (mkName "eqTen", ExprHash 3),
            (mkName "fmapSum", ExprHash 4)
          ]

unsafeGetExpr :: Text -> Expr
unsafeGetExpr input =
  case evaluateText mempty input of
    Right (_, expr', _) -> expr'
    _ -> error "oh no"

eval :: StoreEnv -> Text -> IO (Either Text (MonoType, Expr))
eval env input =
  case evaluateText env input of
    Right (mt, expr', scope') -> do
      endExpr <- interpret scope' expr'
      case endExpr of
        Right a -> pure (Right (mt, a))
        Left e -> pure (Left e)
    Left e -> pure (Left e)

spec :: Spec
spec = do
  describe "Repl" $ do
    describe "End to end parsing to evaluation" $ do
      it "let x = ((1,2)) in fst(x)" $ do
        result <- eval stdLib "let x = ((1,2)) in fst(x)"
        result
          `shouldBe` Right
            (MTInt, int 1)
      it "\\x -> if x then Left 1 else Right \"yes\"" $ do
        result <- eval stdLib "\\x -> if x then Right \"yes\" else Left 1"
        result
          `shouldBe` Right
            ( MTFunction MTBool (MTSum MTInt MTString),
              ( MyLambda
                  (mkName "x")
                  ( MyIf
                      (MyVar (mkName "x"))
                      (MySum MyRight (str' "yes"))
                      (MySum MyLeft (int 1))
                  )
              )
            )
      it "case isTen(9) of Left (\\l -> \"It's not ten\") | Right (\\r -> \"It's ten!\")" $ do
        result <- eval stdLib "case isTen(9) of Left (\\l -> \"It's not ten\") | Right (\\r -> \"It's ten!\")"
        result
          `shouldBe` Right
            (MTString, str' "It's not ten")
        result2 <- eval stdLib "case isTen(10) of Left (\\l -> \"It's not ten\") | Right (\\r -> \"It's ten!\")"
        result2
          `shouldBe` Right
            (MTString, str' "It's ten!")
      it "case (Left 1) of Left (\\l -> Left l) | Right (\\r -> Right r)" $ do
        result <- eval stdLib "case (Left 1) of Left (\\l -> Left l) | Right (\\r -> Right r)"
        result
          `shouldBe` Right
            ( (MTSum MTInt (MTVar (mkName "U1"))),
              ( MySum MyLeft (int 1)
              )
            )
      it "\\sum -> case sum of Left (\\l -> Left l) | Right (\\r -> Right eqTen(r))" $ do
        result <- eval stdLib "\\sum -> case sum of Left (\\l -> Left l) | Right (\\r -> Right eqTen(r))"
        result
          `shouldBe` Right
            ( MTFunction
                (MTSum (MTVar (mkName "U10")) MTInt)
                (MTSum (MTVar (mkName "U10")) MTBool),
              ( MyLambda
                  (mkName "sum")
                  ( MyCase
                      (MyVar (mkName "sum"))
                      ( MyLambda
                          (mkName "l")
                          (MySum MyLeft (MyVar (mkName "l")))
                      )
                      ( MyLambda
                          (mkName "r")
                          ( MySum
                              MyRight
                              ( MyApp
                                  (MyVar (mkName "var0"))
                                  (MyVar (mkName "r"))
                              )
                          )
                      )
                  )
              )
            )
      it "let sum = (Left 1) in ((fmapSum eqTen) sum)" $ do
        result <- eval stdLib "let sum = (Left 1) in fmapSum (eqTen) (sum)"
        result
          `shouldBe` Right
            (MTSum MTInt MTBool, MySum MyLeft (int 1))
