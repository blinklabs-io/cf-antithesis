{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}

module User.Types
    ( TestRun (..)
    , platformL
    , repositoryL
    , directoryL
    , commitIdL
    , tryIndexL
    , requesterL
    , TestRunState (..)
    , TestRunRejection (..)
    , Phase (..)
    , URL (..)
    , RegisterUserKey (..)
    , RegisterRoleKey (..)
    , roleOfATestRun
    , AgentValidation (..)
    )
where

import Control.Applicative (Alternative)
import Control.Lens (makeLensesFor)
import Control.Monad (guard)
import Core.Types
    ( Directory (..)
    , Duration (..)
    , Platform (..)
    , PublicKeyHash (..)
    , Repository (..)
    , SHA1 (..)
    , Try (..)
    , Username (..)
    )
import Data.Map.Strict qualified as Map
import Lib.JSON
    ( getField
    , getIntegralField
    , getListField
    , getStringField
    , getStringMapField
    , intJSON
    , object
    , stringJSON
    , (.:)
    )
import Text.JSON.Canonical
    ( FromJSON (..)
    , JSValue (..)
    , ReportSchemaErrors
    , ToJSON (..)
    , expectedButGotValue
    , fromJSString
    , toJSString
    )

data TestRun = TestRun
    { platform :: Platform
    , repository :: Repository
    , directory :: Directory
    , commitId :: SHA1
    , tryIndex :: Try
    , requester :: Username
    }
    deriving (Eq, Show)

makeLensesFor
    [ ("platform", "platformL")
    , ("repository", "repositoryL")
    , ("directory", "directoryL")
    , ("commitId", "commitIdL")
    , ("tryIndex", "tryIndexL")
    , ("requester", "requesterL")
    ]
    ''TestRun

roleOfATestRun :: TestRun -> RegisterRoleKey
roleOfATestRun
    TestRun
        { platform
        , repository
        , requester = username
        } =
        RegisterRoleKey
            { platform
            , repository
            , username
            }

instance Monad m => ToJSON m TestRun where
    toJSON
        ( TestRun
                (Platform platform)
                (Repository owner repo)
                (Directory directory)
                (SHA1 commitId)
                (Try tryIndex)
                (Username requester)
            ) =
            object
                [ ("platform", stringJSON platform)
                ,
                    ( "repository"
                    , object
                        [ ("organization", stringJSON owner)
                        , ("repo", stringJSON repo)
                        ]
                    )
                , ("directory", stringJSON directory)
                , ("commitId", stringJSON commitId)
                , ("try", intJSON tryIndex)
                , ("requester", stringJSON requester)
                ]

instance (Monad m, ReportSchemaErrors m) => FromJSON m TestRun where
    fromJSON obj@(JSObject _) = do
        mapping <- fromJSON obj
        platform <- getStringField "platform" mapping
        repository <- do
            repoMapping <- getStringMapField "repository" mapping
            owner <- getStringField "organization" repoMapping
            repo <- getStringField "repo" repoMapping
            pure $ Repository{organization = owner, project = repo}
        directory <- getStringField "directory" mapping
        commitId <- getStringField "commitId" mapping
        tryIndex <- getIntegralField "try" mapping
        requester <- getStringField "requester" mapping
        pure
            $ TestRun
                { platform = Platform platform
                , repository = repository
                , directory = Directory directory
                , commitId = SHA1 commitId
                , tryIndex = Try tryIndex
                , requester = Username requester
                }
    fromJSON r =
        expectedButGotValue
            "an object representing a test run"
            r

data Phase = PendingT | DoneT | RunningT

newtype URL = URL String
    deriving (Show, Eq)

data TestRunRejection
    = UnacceptableDuration
    | UnacceptableCommit
    | UnacceptableTryIndex
    | UnacceptableRole
    | AnyReason String
    deriving (Eq, Show)

instance Monad m => ToJSON m TestRunRejection where
    toJSON UnacceptableDuration =
        stringJSON "unacceptable duration"
    toJSON UnacceptableCommit =
        stringJSON "unacceptable commit"
    toJSON UnacceptableTryIndex =
        stringJSON "unacceptable try index"
    toJSON UnacceptableRole =
        stringJSON "unacceptable role"
    toJSON (AnyReason reason) =
        stringJSON reason

instance ReportSchemaErrors m => FromJSON m TestRunRejection where
    fromJSON (JSString jsString) = do
        let reason = fromJSString jsString
        case reason of
            "unacceptable duration" -> pure UnacceptableDuration
            "unacceptable commit" -> pure UnacceptableCommit
            "unacceptable try index" -> pure UnacceptableTryIndex
            "unacceptable requester" -> pure UnacceptableRole
            _ -> pure $ AnyReason reason
    fromJSON other =
        expectedButGotValue "a string representing a reason" other

data TestRunState a where
    Pending :: Duration -> TestRunState PendingT
    Rejected
        :: TestRunState PendingT -> [TestRunRejection] -> TestRunState DoneT
    Accepted :: TestRunState PendingT -> TestRunState RunningT
    Finished
        :: TestRunState RunningT -> Duration -> URL -> TestRunState DoneT

deriving instance Eq (TestRunState a)
deriving instance Show (TestRunState a)
instance Monad m => ToJSON m (TestRunState a) where
    toJSON (Pending (Duration d)) =
        object
            [ ("phase", stringJSON "pending")
            , ("duration", intJSON d)
            ]
    toJSON (Rejected pending reasons) =
        object
            [ ("phase", stringJSON "rejected")
            , ("from", toJSON pending)
            , ("reasons", traverse toJSON reasons >>= toJSON)
            ]
    toJSON (Accepted pending) =
        object
            [ ("phase", stringJSON "accepted")
            , ("from", toJSON pending)
            ]
    toJSON (Finished running duration url) =
        object
            [ ("phase", stringJSON "finished")
            , ("from", toJSON running)
            , ("duration", intJSON $ case duration of Duration d -> d)
            , ("url", stringJSON $ case url of URL u -> u)
            ]

instance ReportSchemaErrors m => FromJSON m (TestRunState PendingT) where
    fromJSON obj@(JSObject _) = do
        mapping <- fromJSON obj
        phase <- getStringField "phase" mapping
        case phase of
            "pending" -> do
                duration <- getIntegralField "duration" mapping
                pure $ Pending (Duration duration)
            _ ->
                expectedButGotValue
                    "a pending phase"
                    obj
    fromJSON other =
        expectedButGotValue
            "an object representing a pending phase"
            other

instance ReportSchemaErrors m => FromJSON m (TestRunState DoneT) where
    fromJSON obj@(JSObject _) = do
        mapping <- fromJSON obj
        phase <- getStringField "phase" mapping
        case phase of
            "rejected" -> do
                pending <- getField "from" mapping >>= fromJSON
                reasons <- getListField "reasons" mapping
                reasonList <- traverse fromJSON reasons
                pure $ Rejected pending reasonList
            "finished" -> do
                running <- getField "from" mapping >>= fromJSON
                duration <- getIntegralField "duration" mapping
                url <- getStringField "url" mapping
                pure $ Finished running (Duration duration) (URL url)
            _ ->
                expectedButGotValue
                    "a rejected phase"
                    obj
    fromJSON other =
        expectedButGotValue
            "an object representing a rejected phase"
            other

instance ReportSchemaErrors m => FromJSON m (TestRunState RunningT) where
    fromJSON obj@(JSObject _) = do
        mapping <- fromJSON obj
        phase <- getStringField "phase" mapping
        case phase of
            "accepted" -> do
                pending <- getField "from" mapping >>= fromJSON
                pure $ Accepted pending
            _ ->
                expectedButGotValue
                    "an accepted phase"
                    obj
    fromJSON other =
        expectedButGotValue
            "an object representing an accepted phase"
            other

data RegisterUserKey = RegisterUserKey
    { platform :: Platform
    , username :: Username
    , pubkeyhash :: PublicKeyHash
    }
    deriving (Eq, Show)

instance Monad m => ToJSON m RegisterUserKey where
    toJSON
        ( RegisterUserKey
                (Platform platform)
                (Username user)
                (PublicKeyHash pubkeyhash)
            ) =
            toJSON
                $ Map.fromList
                    [ ("type", JSString $ toJSString "register-user")
                    , ("platform" :: String, JSString $ toJSString platform)
                    , ("user", JSString $ toJSString user)
                    , ("publickeyhash", JSString $ toJSString pubkeyhash)
                    ]

instance
    (Alternative m, Monad m, ReportSchemaErrors m)
    => FromJSON m RegisterUserKey
    where
    fromJSON obj@(JSObject _) = do
        mapping <- fromJSON obj
        requestType <- mapping .: "type"
        guard $ requestType == JSString "register-user"
        platform <- getStringField "platform" mapping
        user <- getStringField "user" mapping
        pubkeyhash <- getStringField "publickeyhash" mapping
        pure
            $ RegisterUserKey
                { platform = Platform platform
                , username = Username user
                , pubkeyhash = PublicKeyHash pubkeyhash
                }
    fromJSON r =
        expectedButGotValue
            "an object representing an accepted phase"
            r

data RegisterRoleKey = RegisterRoleKey
    { platform :: Platform
    , repository :: Repository
    , username :: Username
    }
    deriving (Eq, Show)

instance (ReportSchemaErrors m, Alternative m) => FromJSON m RegisterRoleKey where
    fromJSON obj@(JSObject _) = do
        mapping <- fromJSON obj
        requestType <- mapping .: "type"
        guard $ requestType == JSString "register-role"
        platform <- mapping .: "platform"
        repository <- do
            repoMapping <- mapping .: "repository"
            owner <- repoMapping .: "organization"
            repo <- repoMapping .: "project"
            pure $ Repository{organization = owner, project = repo}
        user <- mapping .: "user"
        pure
            $ RegisterRoleKey
                { platform = Platform platform
                , repository = repository
                , username = Username user
                }
    fromJSON r =
        expectedButGotValue
            "an object representing a register role"
            r

instance Monad m => ToJSON m RegisterRoleKey where
    toJSON
        ( RegisterRoleKey
                (Platform platform)
                (Repository owner repo)
                (Username user)
            ) =
            object
                [ ("type", stringJSON "register-role")
                , ("platform", stringJSON platform)
                ,
                    ( "repository"
                    , object
                        [ ("organization", stringJSON owner)
                        , ("project", stringJSON repo)
                        ]
                    )
                , ("user", stringJSON user)
                ]

data AgentValidation = AgentValidation
    { testRun :: TestRun
    , validation :: Maybe [TestRunRejection]
    }

instance Monad m => ToJSON m AgentValidation where
    toJSON AgentValidation{testRun, validation} =
        object
            [ ("testRun", toJSON testRun)
            ,
                ( "validation"
                , maybe (pure JSNull) toJSON validation
                )
            ]
instance ReportSchemaErrors m => FromJSON m AgentValidation where
    fromJSON obj@(JSObject _) = do
        mapping <- fromJSON obj
        testRun <- mapping .: "testRun"
        validation <- mapping .: "validation"
        reasons <- case validation of
            JSNull -> pure Nothing
            _ -> Just <$> fromJSON validation
        pure $ AgentValidation{testRun = testRun, validation = reasons}
    fromJSON r =
        expectedButGotValue
            "an object representing an agent validation"
            r
