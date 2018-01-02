{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Hledger.Cli.Commands.Equity (
  equitymode
 ,equity
) 
where

import Data.Maybe
import Data.String.Here
import Data.Time.Calendar
import Hledger
import Hledger.Cli.CliOptions

equitymode = hledgerCommandMode
  [here| equity
Print a "closing balances" transaction that brings all accounts (or with
query arguments, just the matched accounts) to a zero balance, followed by an
opposite "opening balances" transaction that restores the balances from zero.

FLAGS

The opening transaction is useful to carry over asset/liability balances 
if you choose to start a new journal file, eg yearly. The closing transaction
can be a useful complement, allowing you to optionally include old files 
(for more history) without disturbing the asset/liability balances 
(since the closing/opening pairs cancel out).

This command may also be useful for closing out expense/income accounts 
for a period (ie "closing the books" in accounting).

The closing transaction asserts a zero balance for each closed account.

By default, the closing transaction is dated yesterday, with balances 
calculated as of end of yesterday, and the opening transaction is dated today.
To close on some other date, use: `hledger close -e OPENINGDATE ...`

For example, carrying asset/liability balances into a new file for 2018:
```
$ hledger equity -f 2017.journal -e 2018/1/1 ^assets ^liab >>2017.journal
# cut & paste the opening transaction from 2017.journal to a new 2018.journal
# now:
$ hledger bs -f 2018.journal                   # correct balances
$ hledger bs -f 2018.journal -f 2017.journal   # still correct
$ hledger bs -f 2017.journal not:desc:closing  # must exclude closing txn 
```

Possible issues/complications/todos:
- -p or date: should work as well as -e, but can be buggy
- a begin date should have no effect. Closed balances should be historical.
- transactions on the opening date should be excluded from closed balances 
- balance assertions can fail due to filtering by status or realness
- transactions spanning a file boundary, eg:
```
2017/12/31
    expenses:food          1
    assets:bank:checking  -1  ; date:2018/1/1
```
  |]
  []
  [generalflagsgroup1]
  []
  ([], Just $ argsFlag "[QUERY]")

equity CliOpts{reportopts_=ropts} j = do
  today <- getCurrentDay
  let 
      -- TODO: this query is sometimes wrong 
      ropts_ = ropts{accountlistmode_=ALFlat}
      q = queryFromOpts today ropts_
      openingdate = fromMaybe today $ queryEndDate False q
      closingdate = addDays (-1) openingdate
      (acctbals,_) = balanceReport ropts_ q j
      balancingamt = negate $ sum $ map (\(_,_,_,b) -> normaliseMixedAmountSquashPricesForDisplay b) acctbals
      ps = [posting{paccount=a
                   ,pamount=mixed [b]
                   ,pbalanceassertion=Just (b,nullsourcepos)
                   }
           |(a,_,_,mb) <- acctbals
           ,b <- amounts $ normaliseMixedAmountSquashPricesForDisplay mb
           ]
           ++ [posting{paccount="equity:opening balances", pamount=balancingamt}]
      nps = [posting{paccount=a
                    ,pamount=mixed [negate b]
                    ,pbalanceassertion=Just (b{aquantity=0}, nullsourcepos)
                    }
            |(a,_,_,mb) <- acctbals
            ,b <- amounts $ normaliseMixedAmountSquashPricesForDisplay mb
            ]
           ++ [posting{paccount="equity:closing balances", pamount=negate balancingamt}]
  putStr $ showTransaction (nulltransaction{tdate=closingdate, tdescription="closing balances", tpostings=nps})
  putStr $ showTransaction (nulltransaction{tdate=openingdate, tdescription="opening balances", tpostings=ps})
