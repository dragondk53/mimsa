{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE TypeOperators #-}

module Server.Endpoints.Project.AddUnitTest
  ( addUnitTestHandler,
    AddUnitTest,
  )
where

import qualified Data.Aeson as JSON
import Data.OpenApi
import Data.Text (Text)
import GHC.Generics
import qualified Language.Mimsa.Actions.AddUnitTest as Actions
import qualified Language.Mimsa.Actions.Helpers.Parse as Actions
import Language.Mimsa.Tests.Types
import Language.Mimsa.Types.Project
import Servant
import Server.Handlers
import Server.Helpers.TestData
import Server.MimsaHandler
import Server.Types

------

type AddUnitTest =
  "tests" :> "add"
    :> ReqBody '[JSON] AddUnitTestRequest
    :> JsonPost AddUnitTestResponse

data AddUnitTestRequest = AddUnitTestRequest
  { autProjectHash :: ProjectHash,
    autTestName :: TestName,
    autExpression :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (JSON.FromJSON, ToSchema)

data AddUnitTestResponse = AddUnitTestResponse
  { autProjectData :: ProjectData,
    autTestResult :: TestData
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (JSON.ToJSON, ToSchema)

addUnitTestHandler ::
  MimsaEnvironment ->
  AddUnitTestRequest ->
  MimsaHandler AddUnitTestResponse
addUnitTestHandler mimsaEnv (AddUnitTestRequest hash testName testInput) = runMimsaHandlerT $ do
  let action = do
        expr <- Actions.parseExpr testInput
        Actions.addUnitTest expr testName testInput
  response <-
    lift $ eitherFromActionM mimsaEnv hash action
  case response of
    Right (newProject, _, unitTest) -> do
      pd <- lift $ projectDataHandler mimsaEnv newProject
      tests <-
        lift $
          runTestsHandler
            mimsaEnv
            newProject
            [unitTest]
      returnMimsa $
        AddUnitTestResponse
          pd
          (makeTestData newProject tests)
    Left e -> throwMimsaError e
