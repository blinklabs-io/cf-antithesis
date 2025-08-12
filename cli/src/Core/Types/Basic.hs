{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE StrictData #-}

module Core.Types.Basic
    ( Address (..)
    , Commit (..)
    , Directory (..)
    , Duration (..)
    , Host (..)
    , Owner (..)
    , Platform (..)
    , Port (..)
    , PublicKeyHash (..)
    , Repository (..)
    , RequestRefId (..)
    , TokenId (..)
    , Try (..)
    , Username (..)
    , organizationL
    , projectL
    )
where

import Control.Lens (Lens', Wrapped)
import Data.Aeson qualified as Aeson
import Data.ByteString.Base16 (encode)
import Data.ByteString.Char8 qualified as B
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic (Rep))
import Lib.JSON.Canonical.Extra (object, stringJSON)
import PlutusTx (Data (..), builtinDataToData)
import PlutusTx.IsData.Class (FromData (..))
import Servant.API (FromHttpApiData (..), ToHttpApiData (..))
import Text.JSON.Canonical
    ( FromJSON (..)
    , ReportSchemaErrors (..)
    , ToJSON (..)
    )

-- TxHash-OutputIndex
newtype RequestRefId = RequestRefId
    { requestId :: Text
    }
    deriving (Eq, Show)

instance ToHttpApiData RequestRefId where
    toUrlPiece (RequestRefId rid) = rid

instance FromHttpApiData RequestRefId where
    parseUrlPiece rid =
        case rid of
            "" -> Left "RequestRefId cannot be empty"
            _ -> Right (RequestRefId rid)

instance (Monad m) => ToJSON m RequestRefId where
    toJSON (RequestRefId ref) = toJSON ref

instance (ReportSchemaErrors m) => FromJSON m RequestRefId where
    fromJSON v = RequestRefId <$> fromJSON v

instance Aeson.ToJSON RequestRefId where
    toJSON (RequestRefId ref) = Aeson.String ref

instance Aeson.FromJSON RequestRefId where
    parseJSON = Aeson.withText "RequestRefId" $ \txt ->
        pure $ RequestRefId txt

newtype TokenId = TokenId String
    deriving (Eq, Show)

instance (Monad m) => ToJSON m TokenId where
    toJSON (TokenId tokenId) = toJSON tokenId

instance (ReportSchemaErrors m) => FromJSON m TokenId where
    fromJSON v = TokenId <$> fromJSON v

instance FromData TokenId where
    fromBuiltinData = parse . builtinDataToData
      where
        parse = \case
            Constr 0 [B b] -> Just (TokenId $ B.unpack $ encode b)
            _ -> Nothing

instance ToHttpApiData TokenId where
    toUrlPiece (TokenId tokenId) = T.pack tokenId

instance FromHttpApiData TokenId where
    parseUrlPiece tokenId =
        case T.unpack tokenId of
            "" -> Left "TokenId cannot be empty"
            _ -> Right (TokenId (T.unpack tokenId))

newtype Owner = Owner String
    deriving (Eq, Show)

instance (Monad m) => ToJSON m Owner where
    toJSON (Owner owner) = toJSON owner

instance (ReportSchemaErrors m) => FromJSON m Owner where
    fromJSON v = Owner <$> fromJSON v

instance FromData Owner where
    fromBuiltinData = parse . builtinDataToData
      where
        parse = \case
            B b -> Just (Owner $ B.unpack $ encode b)
            _ -> Nothing

newtype Platform = Platform String
    deriving (Eq, Show, Generic)

instance (Monad m) => ToJSON m Platform where
    toJSON (Platform platform) = stringJSON platform

instance Wrapped Platform

newtype PublicKeyHash = PublicKeyHash String
    deriving (Eq, Show)

newtype Commit = Commit String
    deriving (Eq, Show, Generic)

instance Wrapped Commit

newtype Directory = Directory String
    deriving (Eq, Show, Generic)

instance Wrapped Directory

newtype Username = Username String
    deriving (Eq, Show, Generic)

instance Wrapped Username

data Repository = Repository
    { organization :: String
    , project :: String
    }
    deriving (Eq, Show)

instance (Monad m) => ToJSON m Repository where
    toJSON
        (Repository owner repo) =
            object
                [ ("organization", stringJSON owner)
                , ("repo", stringJSON repo)
                ]

organizationL :: Lens' Repository String
organizationL f (Repository org proj) = (`Repository` proj) <$> f org

projectL :: Lens' Repository String
projectL f (Repository org proj) = Repository org <$> f proj

newtype Port = Port Int
    deriving (Eq, Show)

newtype Host = Host String
    deriving (Eq, Show)

newtype Address = Address Text
    deriving (Eq, Show)

instance (Monad m) => ToJSON m Address where
    toJSON (Address addr) = toJSON addr

instance (ReportSchemaErrors m) => FromJSON m Address where
    fromJSON v = Address <$> fromJSON v

instance FromHttpApiData Address where
    parseUrlPiece addr =
        if T.null addr
            then Left "Address cannot be empty"
            else Right (Address addr)

instance ToHttpApiData Address where
    toUrlPiece (Address addr) = addr

newtype Duration = Duration Int
    deriving (Eq, Show)

newtype Try = Try Int
    deriving (Eq, Show, Ord, Enum, Num, Generic)

instance Wrapped Try
