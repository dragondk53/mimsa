{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Actions.AddUnitTest
  ( spec,
  )
where

import Data.Either (isLeft)
import Data.Functor
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Language.Mimsa.Actions.AddUnitTest as Actions
import qualified Language.Mimsa.Actions.BindExpression as Actions
import qualified Language.Mimsa.Actions.Monad as Actions
import Language.Mimsa.Printer
import Language.Mimsa.Tests.Test
import Language.Mimsa.Tests.Types
import Language.Mimsa.Types.AST
import Language.Mimsa.Types.Identifiers
import Language.Mimsa.Types.Store
import Test.Data.Project
import Test.Hspec
import Test.Utils.Helpers

brokenExpr :: Expr Name Annotation
brokenExpr = MyInfix mempty Equals (int 1) (bool True)

testWithIdInExpr :: Expr Name Annotation
testWithIdInExpr =
  MyInfix
    mempty
    Equals
    (MyApp mempty (MyVar mempty "id") (int 1))
    (int 1)

testWithIdAndConst :: Expr Name Annotation
testWithIdAndConst = unsafeParseExpr "id 1 == (const 1 False)" $> mempty

propertyTestWithIdAndConst :: Expr Name Annotation
propertyTestWithIdAndConst =
  unsafeParseExpr "\\a -> id a == (const a False)" $> mempty

idHash :: ExprHash
idHash = getHashOfName testStdlib "id"

spec :: Spec
spec = do
  describe "AddUnitTest" $ do
    it "Fails with broken test" $ do
      Actions.run
        testStdlib
        (Actions.addUnitTest brokenExpr (TestName "Oh no") "1 == True")
        `shouldSatisfy` isLeft
    it "Adds a new unit test" $ do
      case Actions.run
        testStdlib
        (Actions.addUnitTest testWithIdInExpr (TestName "Id does nothing") "id 1 == 1") of
        Left _ -> error "Should not have failed"
        Right (newProject, outcomes, _) -> do
          -- one more item in store
          additionalStoreItems testStdlib newProject
            `shouldBe` 1
          -- one more unit test
          additionalTests testStdlib newProject
            `shouldBe` 1
          -- new expression
          S.size (Actions.storeExpressionsFromOutcomes outcomes) `shouldBe` 1

    it "Adds a new property test" $ do
      case Actions.run
        testStdlib
        ( Actions.addUnitTest
            propertyTestWithIdAndConst
            (TestName "Id does nothing")
            (prettyPrint propertyTestWithIdAndConst)
        ) of
        Left _ -> error "Should not have failed"
        Right (newProject, outcomes, _) -> do
          -- one more item in store
          additionalStoreItems testStdlib newProject
            `shouldBe` 1
          -- one more unit test
          additionalTests testStdlib newProject
            `shouldBe` 1
          -- new expression
          S.size (Actions.storeExpressionsFromOutcomes outcomes) `shouldBe` 1

    it "Adds a new unit test, updates it's dep, but retrieving only returns one version" $ do
      let newConst =
            MyLambda
              mempty
              (Identifier mempty "aaa")
              (MyLambda mempty (Identifier mempty "bbb") (MyVar mempty "aaa"))
      case Actions.run
        testStdlib
        ( do
            _ <- Actions.addUnitTest testWithIdAndConst (TestName "Id does nothing") (prettyPrint testWithIdAndConst)
            Actions.bindExpression newConst "const" (prettyPrint newConst)
        ) of
        Left e -> error (T.unpack $ prettyPrint e)
        Right (newProject, _, _) -> do
          additionalTests testStdlib newProject `shouldBe` 2
          -- When actually fetching tests we should only show one for id
          -- instead of for both versions of `const`
          let gotTests = getTestsForExprHash newProject idHash
          length gotTests `shouldBe` 1

    it "Adds a new property test, updates it's dep, but retrieving only returns one version" $ do
      let newConst =
            MyLambda
              mempty
              (Identifier mempty "aaa")
              (MyLambda mempty (Identifier mempty "bbb") (MyVar mempty "aaa"))
      case Actions.run
        testStdlib
        ( do
            _ <-
              Actions.addUnitTest
                propertyTestWithIdAndConst
                (TestName "Id does nothing")
                (prettyPrint propertyTestWithIdAndConst)
            Actions.bindExpression newConst "const" (prettyPrint newConst)
        ) of
        Left e -> error (T.unpack $ prettyPrint e)
        Right (newProject, _, _) -> do
          additionalTests testStdlib newProject `shouldBe` 2
          -- When actually fetching tests we should only show one for id
          -- instead of for both versions of `const`
          let gotTests = getTestsForExprHash newProject idHash
          length gotTests `shouldBe` 1
