module Cli
    ( cmd
    , Command (..)
    ) where

import Control.Monad.IO.Class (MonadIO (..))
import Core.Types.Basic (Owner (Owner), RequestRefId, TokenId)
import Core.Types.Tx (TxHash, WithTxHash (..))
import Core.Types.Wallet (Wallet)
import Data.Aeson (eitherDecodeFileStrict')
import Lib.SSH.Private
    ( KeyAPI (..)
    , SSHKeySelector (SSHKeySelector)
    , SigningMap
    )
import MPFS.API (getTokenFacts, retractChange)
import Oracle.Cli (OracleCommand (..), oracleCmd)
import Oracle.Validate.Requests.TestRun.Config
    ( TestRunValidationConfig (..)
    )
import Servant.Client (ClientM)
import Submitting (Submitting, signAndSubmit)
import System.Environment (getEnv)
import Text.JSON.Canonical (JSValue)
import User.Agent.Cli
    ( AgentCommand (..)
    , IsReady (NotReady)
    , agentCmd
    )
import User.Requester.Cli
    ( RequesterCommand
    , requesterCmd
    )
import Wallet.Cli (WalletCommand, walletCmd)

data Command a where
    RequesterCommand :: RequesterCommand a -> Command a
    OracleCommand :: OracleCommand a -> Command a
    AgentCommand :: AgentCommand NotReady a -> Command a
    RetractRequest
        :: { outputReference :: RequestRefId
           }
        -> Command TxHash
    GetFacts :: Command JSValue
    Wallet :: WalletCommand a -> Command a

deriving instance Show (Command a)
deriving instance Eq (Command a)

cmd
    :: Submitting
    -> Either FilePath Wallet
    -> Maybe SigningMap
    -> Maybe TokenId
    -> Command a
    -> ClientM a
cmd sbmt mwf msign tokenId command = do
    cfg <- liftIO $ do
        configFile <- getEnv "ANTI_CONFIG_FILE"
        config <-
            eitherDecodeFileStrict' configFile
                :: IO (Either String TestRunValidationConfig)
        case config of
            Left err -> error $ "Failed to parse config file: " ++ err
            Right cfg -> pure cfg
    cmdCore sbmt cfg mwf msign tokenId command

failNothing :: Applicative m => [Char] -> Maybe a -> m a
failNothing w Nothing = error w
failNothing _ (Just x) = pure x

failLeft :: Applicative m => (a -> String) -> Either a b -> m b
failLeft f (Left err) = error $ f err
failLeft _ (Right x) = pure x

cmdCore
    :: Submitting
    -> TestRunValidationConfig
    -> Either FilePath Wallet
    -> Maybe SigningMap
    -> Maybe TokenId
    -> Command a
    -> ClientM a
cmdCore
    sbmt
    testRunValidationConfig
    mWallet
    mSigning
    mTokenId = \case
        RequesterCommand requesterCommand -> do
            signing <- failNothing "No SSH file" mSigning
            sshKeySelector <- liftIO $ getEnv "ANTI_SSH_KEY_SELECTOR"
            keyAPI <-
                failNothing (sshKeySelector <> "not in the signing map")
                    $ signing
                    $ SSHKeySelector sshKeySelector
            tokenId <- failNothing "No TokenId" mTokenId
            wallet <- failLeft ("No wallet @ " <>) mWallet
            requesterCmd
                sbmt
                wallet
                testRunValidationConfig
                tokenId
                (sign keyAPI)
                requesterCommand
        OracleCommand oracleCommand -> do
            wallet <- failLeft ("No wallet @ " <>) mWallet
            antithesisPKH <-
                liftIO $ Owner <$> getEnv "ANTI_AGENT_PUBLIC_KEY_HASH"
            oracleCmd
                sbmt
                wallet
                testRunValidationConfig
                antithesisPKH
                mTokenId
                oracleCommand
        AgentCommand agentCommand -> do
            antithesisPKH <-
                liftIO $ Owner <$> getEnv "ANTI_AGENT_PUBLIC_KEY_HASH"
            tokenId <- failNothing "No TokenId" mTokenId
            wallet <- failLeft ("No wallet @ " <>) mWallet
            agentCmd sbmt wallet tokenId antithesisPKH agentCommand
        RetractRequest refId -> do
            wallet <- failLeft ("No wallet @ " <>) mWallet
            fmap txHash $ signAndSubmit sbmt wallet $ \address ->
                retractChange address refId
        GetFacts -> do
            tokenId <- failNothing "No TokenId" mTokenId
            getTokenFacts tokenId
        Wallet walletCommand -> do
            liftIO $ case mWallet of
                Right wallet -> walletCmd (Right wallet) walletCommand
                Left walletFile -> walletCmd (Left walletFile) walletCommand
