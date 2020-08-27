{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module Language.Mimsa.Types.AST
  ( Expr (..),
    Literal (..),
    FuncName (..),
    StringType (..),
  )
where

import qualified Data.Aeson as JSON
import Data.Map (Map)
import qualified Data.Map as M
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics
import Language.Mimsa.Types.Construct
import Language.Mimsa.Types.Name
import Language.Mimsa.Types.Printer
import Language.Mimsa.Types.TypeName

------------

newtype StringType = StringType Text
  deriving newtype (Eq, Ord, Show, JSON.FromJSON, JSON.ToJSON)

instance Printer StringType where
  prettyPrint (StringType s) = s

--------

newtype FuncName = FuncName Text
  deriving stock (Eq, Ord, Generic)
  deriving newtype (Show, JSON.FromJSON, JSON.ToJSON)

instance Printer FuncName where
  prettyPrint (FuncName a) = a

-------

data Literal
  = MyInt Int
  | MyBool Bool
  | MyString StringType
  | MyUnit
  deriving (Eq, Ord, Show, Generic, JSON.FromJSON, JSON.ToJSON)

instance Printer Literal where
  prettyPrint (MyInt i) = T.pack (show i)
  prettyPrint (MyBool True) = "True"
  prettyPrint (MyBool False) = "False"
  prettyPrint (MyString str) = "\"" <> prettyPrint str <> "\""
  prettyPrint MyUnit = "Unit"

-------

data Expr a
  = MyLiteral Literal
  | MyVar a
  | MyLet a (Expr a) (Expr a) -- binder, expr, body
  | MyLetPair a a (Expr a) (Expr a) -- binderA, binderB, expr, body
  | MyLambda a (Expr a) -- binder, body
  | MyApp (Expr a) (Expr a) -- function, argument
  | MyIf (Expr a) (Expr a) (Expr a) -- expr, thencase, elsecase
  | MyPair (Expr a) (Expr a) -- (a,b)
  | MyRecord (Map Name (Expr a)) -- { dog: MyLiteral (MyInt 1), cat: MyLiteral (MyInt 2) }
  | MyRecordAccess (Expr a) Name -- a.foo
  | MyData Construct [Name] (Map Construct [TypeName]) (Expr a) -- tyName, tyArgs, Map constructor args, body
  | MyConstructor Construct -- use a constructor by name
  | MyConsApp (Expr a) (Expr a) -- constructor, value
  | MyCaseMatch (Expr a) [(Construct, Expr a)] (Maybe (Expr a)) -- expr, matches, catchAll
  deriving (Eq, Ord, Show, Generic, JSON.FromJSON, JSON.ToJSON)

instance (Printer a) => Printer (Expr a) where
  prettyPrint (MyLiteral l) = prettyPrint l
  prettyPrint (MyVar var) = prettyPrint var
  prettyPrint (MyLet var expr1 expr2) =
    "let " <> prettyPrint var
      <> " = "
      <> printSubExpr expr1
      <> " in "
      <> printSubExpr expr2
  prettyPrint (MyLetPair var1 var2 expr1 body) =
    "let (" <> prettyPrint var1 <> ", " <> prettyPrint var2
      <> ") = "
      <> printSubExpr expr1
      <> " in "
      <> printSubExpr body
  prettyPrint (MyLambda binder expr) =
    "\\"
      <> prettyPrint binder
      <> " -> "
      <> printSubExpr expr
  prettyPrint (MyApp (MyApp (MyApp func arg1) arg2) arg3) =
    printSubExpr func <> "("
      <> printSubExpr arg1
      <> ")("
      <> printSubExpr arg2
      <> ")("
      <> printSubExpr arg3
      <> ")"
  prettyPrint (MyApp (MyApp func arg1) arg2) =
    printSubExpr func <> "("
      <> printSubExpr arg1
      <> ")("
      <> printSubExpr arg2
      <> ")"
  prettyPrint (MyApp func arg) =
    printSubExpr func <> "("
      <> printSubExpr arg
      <> ")"
  prettyPrint (MyRecordAccess expr name) =
    printSubExpr expr <> "." <> prettyPrint name
  prettyPrint (MyIf if' then' else') =
    "if "
      <> printSubExpr if'
      <> " then "
      <> printSubExpr then'
      <> " else "
      <> printSubExpr else'
  prettyPrint (MyPair a b) =
    "("
      <> printSubExpr a
      <> ", "
      <> printSubExpr b
      <> ")"
  prettyPrint (MyRecord map') = "{" <> T.intercalate ", " exprs' <> "}"
    where
      exprs' =
        ( \(name, val) ->
            prettyPrint name
              <> ": "
              <> printSubExpr val
        )
          <$> M.toList map'
  prettyPrint (MyData tyName tyArgs constructors expr) =
    "type " <> prettyPrint tyName
      <> T.intercalate " " (prettyPrint <$> tyArgs)
      <> " "
      <> T.intercalate " | " (printCons <$> M.toList constructors)
      <> " in "
      <> printSubExpr expr
    where
      printCons (consName, args) =
        prettyPrint consName <> " " <> T.intercalate " " (prettyPrint <$> args)
  prettyPrint (MyConstructor name) = prettyPrint name
  prettyPrint (MyConsApp fn val) = prettyPrint fn <> " " <> prettyPrint val
  prettyPrint (MyCaseMatch sumExpr matches catchAll) =
    "case "
      <> printSubExpr sumExpr
      <> " of "
      <> T.intercalate " | " (printMatch <$> matches)
      <> maybe "" (\catchExpr -> " | otherwise " <> printSubExpr catchExpr) catchAll
    where
      printMatch (construct, expr') =
        prettyPrint construct <> " " <> printSubExpr expr'

inParens :: (Printer a) => a -> Text
inParens a = "(" <> prettyPrint a <> ")"

-- print simple things with no brackets, and complex things inside brackets
printSubExpr :: (Printer a) => Expr a -> Text
printSubExpr expr = case expr of
  all'@MyLet {} -> inParens all'
  all'@MyLambda {} -> inParens all'
  all'@MyApp {} -> inParens all'
  all'@MyIf {} -> inParens all'
  a -> prettyPrint a
-----------------
