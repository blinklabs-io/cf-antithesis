{-# LANGUAGE FlexibleContexts #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module User.TypesSpec
    ( spec
    )
where

import Core.Types.Basic
    ( Commit (Commit)
    , Directory (Directory)
    , Duration (..)
    , Platform (Platform)
    , PublicKeyHash (..)
    , Repository (Repository, organization, project)
    , Try (..)
    , Username (Username)
    )
import Test.Hspec (Spec, describe, it)
import Test.Hspec.Canonical (roundTrip)
import Test.QuickCheck
    ( ASCIIString (..)
    , Gen
    , Testable (..)
    , elements
    , forAll
    , forAllBlind
    , listOf
    )
import Test.QuickCheck.Crypton (sshGen)
import User.Types
    ( RegisterUserKey (..)
    , TestRun (..)
    , TestRunRejection (..)
    , TestRunState (..)
    , URL (..)
    )

testRunRejectionGen :: Gen TestRunRejection
testRunRejectionGen = do
    elements
        [ BrokenInstructions
        , UnclearIntent
        ]

spec :: Spec
spec = do
    describe "TestRun" $ do
        it "roundtrips on the JSON instance" $ do
            let testRun =
                    TestRun
                        { platform = Platform "github"
                        , repository =
                            Repository
                                { organization = "user"
                                , project = "repo"
                                }
                        , commitId = Commit "abc123"
                        , directory = Directory "src"
                        , requester = Username "tester"
                        , tryIndex = Try 1
                        }
            roundTrip testRun

    describe "TestRunState" $ do
        it "roundtrips on the JSON instance"
            $ property
            $ \message
               duration
               (ASCIIString url) -> forAll (listOf testRunRejectionGen) $ \rejections -> do
                    forAllBlind sshGen $ \(sign, _verify) -> do
                        let pending = Pending (Duration duration) $ sign message
                        roundTrip pending
                        let rejected =
                                Rejected
                                    pending
                                    rejections
                        roundTrip rejected
                        let accepted = Accepted pending
                        roundTrip accepted
                        let finished =
                                Finished
                                    accepted
                                    (Duration duration)
                                    (URL url)
                        roundTrip finished

    describe "RegisterUserKey" $ do
        it "roundtrips on the JSON instance" $ do
            let registerPubKey =
                    RegisterUserKey
                        { platform = Platform "github"
                        , username = Username "tester"
                        , pubkeyhash =
                            PublicKeyHash
                                "AAAAC3NzaC1lZDI1NTE5AAAAIO773JHqlyLm5XzOjSe+Q5yFJyLFuMLL6+n63t4t7HR8"
                        }
            roundTrip registerPubKey
