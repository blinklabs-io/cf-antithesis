{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module User.Agent.PublishResults.EmailSpec (spec)
where

import Core.Types.Basic
    ( Commit (Commit)
    , Directory (Directory)
    , Platform (Platform)
    , Repository (Repository, organization, project)
    , Username (Username)
    )
import Data.ByteString qualified as B
import Data.Maybe (fromJust)
import Data.String.QQ (s)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time
    ( UTCTime (..)
    , defaultTimeLocale
    , diffUTCTime
    , parseTimeM
    , secondsToDiffTime
    )
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (Gen, choose, forAll, withMaxSuccess)
import User.Agent.PublishResults.Email
    ( ParsingError (..)
    , Result (..)
    , WithDateError (..)
    , clockTimeToUTCTime
    , readEmail
    , utcTimeToClockTime
    )
import User.Types
    ( TestRun
        ( TestRun
        , commitId
        , directory
        , platform
        , repository
        , requester
        , tryIndex
        )
    )

spec :: Spec
spec = do
    describe "old-time convertion" $ do
        prop "almost roundtrips" $ withMaxSuccess 100000 $ forAll genTime $ \t ->
            diffUTCTime (clockTimeToUTCTime (utcTimeToClockTime t)) t < 1e-9
    describe "email parser" $ do
        it "parses good email"
            $ case readEmail goldenEmail of
                Left _ -> expectationFailure "should parse"
                Right r ->
                    r
                        `shouldBe` Result
                            { description =
                                TestRun
                                    { commitId = Commit "a7741a44dfddfe05822e1a49862ceea43ecd657d"
                                    , directory = Directory "antithesis-test"
                                    , platform = Platform "github"
                                    , repository =
                                        Repository
                                            { organization =
                                                "cardano-foundation"
                                            , project = "hal-fixture-sin"
                                            }
                                    , requester = Username "cfhal"
                                    , tryIndex = 1
                                    }
                            , date =
                                fromJust
                                    $ parseTimeM
                                        True
                                        defaultTimeLocale
                                        "%Y-%m-%d %H:%M:%S"
                                        "2025-09-05 17:27:03"
                            , link = T.strip expectedLink
                            }
        it "rejects email with no date"
            $ case readEmail noDate of
                Left NoDate -> return ()
                Left _ -> expectationFailure "wrong error"
                Right _ -> expectationFailure "should not parse"
        it "rejects email with no description"
            $ case readEmail descriptionMissing of
                Left (WithDate _ DescriptionMissingOrUnusable) -> return ()
                Left _ -> expectationFailure "wrong error"
                Right _ -> expectationFailure "should not parse"
        it "rejects email with no link"
            $ case readEmail linkMissing of
                Left (WithDate _ LinkMissing) -> return ()
                Left _ -> expectationFailure "wrong error"
                Right _ -> expectationFailure "should not parse"
        it "parses quoted-printable email"
            $ case readEmail quotedPrintableGood of
                Left err -> expectationFailure $ "should parse: " <> show err
                Right r ->
                    r
                        `shouldBe` Result
                            { description =
                                TestRun
                                    { commitId = Commit "a7741a44dfddfe05822e1a49862ceea43ecd657d"
                                    , directory = Directory "antithesis-test"
                                    , platform = Platform "github"
                                    , repository =
                                        Repository
                                            { organization = "cardano-foundation"
                                            , project = "hal-fixture-sin"
                                            }
                                    , requester = Username "cfhal"
                                    , tryIndex = 2
                                    }
                            , date =
                                fromJust
                                    $ parseTimeM
                                        True
                                        defaultTimeLocale
                                        "%Y-%m-%d %H:%M:%S"
                                        "2025-09-05 17:27:03"
                            , link =
                                T.strip
                                    [s|https://cardano.antithesis.com/report/nDSj3YOUtIvcco1HRmK7iz2w/YudEq2ITbl0xxDqYNgdrT2gHUMtQDXYkNtDMyRwT61A.html?auth=v2.public.eyJuYmYiOiIyMDI1LTA5LTEzVDExOjAyOjM2LjIwNzY1ODk2NFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiWXVkRXEySVRibDB4eERxWU5nZHJUMmdIVU10UURYWWtOdERNeVJ3VDYxQS5odG1sIiwicmVwb3J0X2lkIjoibkRTajNZT1V0SXZjY28xSFJtSzdpejJ3In19fUQUQv8zIXJj1FqNehObRCWcj22nLkUqxHJCTuO5FN4TK_xN4P9o8luQnFgbwPKH1eAmwrFtC7qMUzlp3kqpoQI|]
                            }

genTime :: Gen UTCTime
genTime = do
    day <- choose (0, 40000)
    sec <- choose (0, 86400)
    pico <- choose (0, floor @Double 1e12)
    return
        $ UTCTime
            { utctDay = toEnum day
            , utctDayTime = secondsToDiffTime sec + toEnum pico
            }

expectedLink :: Text
expectedLink =
    [s|
https://cardano.antithesis.com/report/zMNsYjs1lOgRg0IijZGTB1GN/mcuSRCDOzItEqm33oW5hyJHB-GLiVUEItcy_QHALwNg.html?auth=v2.public.eyJuYmYiOiIyMDI1LTA5LTA1VDE2OjI3OjAwLjE3OTczNTk5OFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoibWN1U1JDRE96SXRFcW0zM29XNWh5SkhCLUdMaVZVRUl0Y3lfUUhBTHdOZy5odG1sIiwicmVwb3J0X2lkIjoiek1Oc1lqczFsT2dSZzBJaWpaR1RCMUdOIn19fXphuf6Ej7hBlNswCpx1nhpDqVndh8T9e-0_huYlJKnckuN9bTSlL8YrbjwBx6J5NrW50gs2EQClq15Ze2J7qQQ
|]

goldenEmail :: B.ByteString
goldenEmail =
    [s|
From: "'Antithesis Reports' via list_antithesis_external" <antithesis@cardanofoundation.org>
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: 7bit
Date: Fri, 5 Sep 2025 17:27:03 +0000

<br>Run by cardano on 2025-09-05 15:59 UTC<br> Description: {"commitId":"a7741a44dfddfe05822e1a49862ceea43ecd657d","directory":"antithesis-test","platform":"github","repository":{"organization":"cardano-foundation","repo":"hal-fixture-sin"},"requester":"cfhal","try":1,"type":"test-run"}<br><span style="font-size:larger;font-weight:bold"><a href=https://cardano.antithesis.com/report/zMNsYjs1lOgRg0IijZGTB1GN/mcuSRCDOzItEqm33oW5hyJHB-GLiVUEItcy_QHALwNg.html?auth=v2.public.eyJuYmYiOiIyMDI1LTA5LTA1VDE2OjI3OjAwLjE3OTczNTk5OFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoibWN1U1JDRE96SXRFcW0zM29XNWh5SkhCLUdMaVZVRUl0Y3lfUUhBTHdOZy5odG1sIiwicmVwb3J0X2lkIjoiek1Oc1lqczFsT2dSZzBJaWpaR1RCMUdOIn19fXphuf6Ej7hBlNswCpx1nhpDqVndh8T9e-0_huYlJKnckuN9bTSlL8YrbjwBx6J5NrW50gs2EQClq15Ze2J7qQQ>View report - 156ddbac4c6eede1268ca1995cb18c4a-37-4</a></span><br><h3>No findings introduced this run.<br><font style="color:orange">2 ongoing</font> issues.</h3>



    <a href="https://cardano.antithesis.com/report/zMNsYjs1lOgRg0IijZGTB1GN/mcuSRCDOzItEqm33oW5hyJHB-GLiVUEItcy_QHALwNg.html?auth=v2.public.eyJuYmYiOiIyMDI1LTA5LTA1VDE2OjI3OjAwLjE3OTczNTk5OFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoibWN1U1JDRE96SXRFcW0zM29XNWh5SkhCLUdMaVZVRUl0Y3lfUUhBTHdOZy5odG1sIiwicmVwb3J0X2lkIjoiek1Oc1lqczFsT2dSZzBJaWpaR1RCMUdOIn19fXphuf6Ej7hBlNswCpx1nhpDqVndh8T9e-0_huYlJKnckuN9bTSlL8YrbjwBx6J5NrW50gs2EQClq15Ze2J7qQQ#/run/156ddbac4c6eede1268ca1995cb18c4a-37-4/findings/2f95173b159955ee457c5f52cbb711791c742ef1,961d3c463f5ef7640df4b3f30c6d7d9d2759b9c7">Look into 2 ongoing findings.</a>

|]

noDate :: B.ByteString
noDate =
    [s|
From: "'Antithesis Reports' via list_antithesis_external" <antithesis@cardanofoundation.org>
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: 7bit

<br>Run by cardano on 2025-09-05 15:59 UTC<br> Description: {"commitId":"a7741a44dfddfe05822e1a49862ceea43ecd657d","directory":"antithesis-test","platform":"github","repository":{"organization":"cardano-foundation","repo":"hal-fixture-sin"},"requester":"cfhal","try":1,"type":"test-run"}<br><span style="font-size:larger;font-weight:bold"><a href=https://cardano.antithesis.com/report/zMNsYjs1lOgRg0IijZGTB1GN/mcuSRCDOzItEqm33oW5hyJHB-GLiVUEItcy_QHALwNg.html?auth=v2.public.eyJuYmYiOiIyMDI1LTA5LTA1VDE2OjI3OjAwLjE3OTczNTk5OFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoibWN1U1JDRE96SXRFcW0zM29XNWh5SkhCLUdMaVZVRUl0Y3lfUUhBTHdOZy5odG1sIiwicmVwb3J0X2lkIjoiek1Oc1lqczFsT2dSZzBJaWpaR1RCMUdOIn19fXphuf6Ej7hBlNswCpx1nhpDqVndh8T9e-0_huYlJKnckuN9bTSlL8YrbjwBx6J5NrW50gs2EQClq15Ze2J7qQQ>View report - 156ddbac4c6eede1268ca1995cb18c4a-37-4</a></span><br><h3>No findings introduced this run.<br><font style="color:orange">2 ongoing</font> issues.</h3>



    <a href="https://cardano.antithesis.com/report/zMNsYjs1lOgRg0IijZGTB1GN/mcuSRCDOzItEqm33oW5hyJHB-GLiVUEItcy_QHALwNg.html?auth=v2.public.eyJuYmYiOiIyMDI1LTA5LTA1VDE2OjI3OjAwLjE3OTczNTk5OFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoibWN1U1JDRE96SXRFcW0zM29XNWh5SkhCLUdMaVZVRUl0Y3lfUUhBTHdOZy5odG1sIiwicmVwb3J0X2lkIjoiek1Oc1lqczFsT2dSZzBJaWpaR1RCMUdOIn19fXphuf6Ej7hBlNswCpx1nhpDqVndh8T9e-0_huYlJKnckuN9bTSlL8YrbjwBx6J5NrW50gs2EQClq15Ze2J7qQQ#/run/156ddbac4c6eede1268ca1995cb18c4a-37-4/findings/2f95173b159955ee457c5f52cbb711791c742ef1,961d3c463f5ef7640df4b3f30c6d7d9d2759b9c7">Look into 2 ongoing findings.</a>

|]

descriptionMissing :: B.ByteString
descriptionMissing =
    [s|
From: "'Antithesis Reports' via list_antithesis_external" <antithesis@cardanofoundation.org>
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: 7bit
Date: Fri, 5 Sep 2025 17:27:03 +0000

<br>Run by cardano on 2025-09-05 15:59 UTC<br> Description: anything<br><span style="font-size:larger;font-weight:bold"><a href=https://cardano.antithesis.com/report/zMNsYjs1lOgRg0IijZGTB1GN/mcuSRCDOzItEqm33oW5hyJHB-GLiVUEItcy_QHALwNg.html?auth=v2.public.eyJuYmYiOiIyMDI1LTA5LTA1VDE2OjI3OjAwLjE3OTczNTk5OFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoibWN1U1JDRE96SXRFcW0zM29XNWh5SkhCLUdMaVZVRUl0Y3lfUUhBTHdOZy5odG1sIiwicmVwb3J0X2lkIjoiek1Oc1lqczFsT2dSZzBJaWpaR1RCMUdOIn19fXphuf6Ej7hBlNswCpx1nhpDqVndh8T9e-0_huYlJKnckuN9bTSlL8YrbjwBx6J5NrW50gs2EQClq15Ze2J7qQQ>View report - 156ddbac4c6eede1268ca1995cb18c4a-37-4</a></span><br><h3>No findings introduced this run.<br><font style="color:orange">2 ongoing</font> issues.</h3>



    <a href="https://cardano.antithesis.com/report/zMNsYjs1lOgRg0IijZGTB1GN/mcuSRCDOzItEqm33oW5hyJHB-GLiVUEItcy_QHALwNg.html?auth=v2.public.eyJuYmYiOiIyMDI1LTA5LTA1VDE2OjI3OjAwLjE3OTczNTk5OFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoibWN1U1JDRE96SXRFcW0zM29XNWh5SkhCLUdMaVZVRUl0Y3lfUUhBTHdOZy5odG1sIiwicmVwb3J0X2lkIjoiek1Oc1lqczFsT2dSZzBJaWpaR1RCMUdOIn19fXphuf6Ej7hBlNswCpx1nhpDqVndh8T9e-0_huYlJKnckuN9bTSlL8YrbjwBx6J5NrW50gs2EQClq15Ze2J7qQQ#/run/156ddbac4c6eede1268ca1995cb18c4a-37-4/findings/2f95173b159955ee457c5f52cbb711791c742ef1,961d3c463f5ef7640df4b3f30c6d7d9d2759b9c7">Look into 2 ongoing findings.</a>

|]

linkMissing :: B.ByteString
linkMissing =
    [s|
From: "'Antithesis Reports' via list_antithesis_external" <antithesis@cardanofoundation.org>
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: 7bit
Date: Fri, 5 Sep 2025 17:27:03 +0000

<br>Run by cardano on 2025-09-05 15:59 UTC<br> Description: {"commitId":"a7741a44dfddfe05822e1a49862ceea43ecd657d","directory":"antithesis-test","platform":"github","repository":{"organization":"cardano-foundation","repo":"hal-fixture-sin"},"requester":"cfhal","try":1,"type":"test-run"}<br><span style="font-size:larger;font-weight:bold"></span><br><h3>No findings introduced this run.<br><font style="color:orange">2 ongoing</font> issues.</h3>





|]
quotedPrintableGood :: B.ByteString
quotedPrintableGood =
    [s|
From: "'Antithesis Reports' via list_antithesis_external" <antithesis@cardanofoundation.org>
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: quoted-printable
Date: Fri, 5 Sep 2025 17:27:03 +0000

<br>Run by cardano on 2025-09-13 09:36 UTC<br> Description: {"testRun":{"co=
mmitId":"a7741a44dfddfe05822e1a49862ceea43ecd657d","directory":"antithesis-=
test","platform":"github","repository":{"organization":"cardano-foundation"=
,"repo":"hal-fixture-sin"},"requester":"cfhal","try":2,"type":"test-run"},"=
testRunId":"0f84dc8e2abf5eefc93c016192225db8482a99bbdac3b114cf32c6832a23e63=
6"}<br><span style=3D"font-size:larger;font-weight:bold"><a href=3Dhttps://=
cardano.antithesis.com/report/nDSj3YOUtIvcco1HRmK7iz2w/YudEq2ITbl0xxDqYNgdr=
T2gHUMtQDXYkNtDMyRwT61A.html?auth=3Dv2.public.eyJuYmYiOiIyMDI1LTA5LTEzVDExO=
jAyOjM2LjIwNzY1ODk2NFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiWXVk=
RXEySVRibDB4eERxWU5nZHJUMmdIVU10UURYWWtOdERNeVJ3VDYxQS5odG1sIiwicmVwb3J0X2l=
kIjoibkRTajNZT1V0SXZjY28xSFJtSzdpejJ3In19fUQUQv8zIXJj1FqNehObRCWcj22nLkUqxH=
JCTuO5FN4TK_xN4P9o8luQnFgbwPKH1eAmwrFtC7qMUzlp3kqpoQI>View report - 8f54a38=
2decd75c13766bcde08c5750a-37-4</a></span><br><h3>No findings introduced thi=
s run.<br><font style=3D"color:orange">1 ongoing</font> issue.</h3>
   =20
   =20
   =20
    <a href=3D"https://cardano.antithesis.com/report/nDSj3YOUtIvcco1HRmK7iz=
2w/YudEq2ITbl0xxDqYNgdrT2gHUMtQDXYkNtDMyRwT61A.html?auth=3Dv2.public.eyJuYm=
YiOiIyMDI1LTA5LTEzVDExOjAyOjM2LjIwNzY1ODk2NFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZ=
VYxIjp7ImFzc2V0IjoiWXVkRXEySVRibDB4eERxWU5nZHJUMmdIVU10UURYWWtOdERNeVJ3VDYx=
QS5odG1sIiwicmVwb3J0X2lkIjoibkRTajNZT1V0SXZjY28xSFJtSzdpejJ3In19fUQUQv8zIXJ=
j1FqNehObRCWcj22nLkUqxHJCTuO5FN4TK_xN4P9o8luQnFgbwPKH1eAmwrFtC7qMUzlp3kqpoQ=
I#/run/8f54a382decd75c13766bcde08c5750a-37-4/finding/2f95173b159955ee457c5f=
52cbb711791c742ef1">Look into 1 ongoing finding.</a>
|]
