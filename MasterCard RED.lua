--
-- MoneyMoney Web Banking MasterCard RED extension
-- http://moneymoney-app.com/api/webbanking
--
--
-- The MIT License (MIT)
--
-- Copyright (c) 2014 Lukas Köll (phpwutz)
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
--
-- Get balance and transactions for MasterCard RED
--

WebBanking{version     = 1.00,
           country     = "de",
           url         = "https://gate.sinsys.net/gui/plb/",
           services    = {"MasterCard RED"},
           description = string.format(MM.localizeText("Get balance and transactions for %s"), "MasterCard RED")}

local xPathes = {
    accountOwner = '/html/body/center/table/tr[3]/td/table/tr[2]/td[4]/b',
    accountNumber = '/html/body/center/table/tr[3]/td/table/tr[3]/td[4]/b',
    bankCode = '/html/body/center/table/tr[3]/td/table/tr[4]/td[4]/b',
    iban = '/html/body/center/table/tr[3]/td/table/tr[3]/td[6]/b',
    bic = '/html/body/center/table/tr[3]/td/table/tr[4]/td[6]/b',
    transactionRows = "//table[@class='gNarrowContentSection']/form/tr[@class='style4']",
    balance = '//html/body/center/table/tr[3]/td/table/tr[4]/td[2]/b',
    localeLinkGerman = '/html/body/form/center/table/tr[1]/td/a[2]'
}


local mcrLoginResponse = {}

function SupportsBank (protocol, bankCode)
  return bankCode == "MasterCard RED" and protocol == "Web Banking"
end

function makeTimeStamp(dateString)
    local pattern = "(%d%d)%/(%d%d)%/(%d%d%d%d)"
    local xday, xmonth, xyear = dateString:match(pattern)
    return os.time({year = xyear, month = xmonth, day = xday})
end


function InitializeSession (protocol, bankCode, username, username2, password, username3)
  local connection = Connection()

  -- change locale to german so we can detect 'Aufladung'
  local loginPage = HTML(connection:get(url))

  local germanLocaleLink = loginPage:xpath(xPathes.localeLinkGerman)
  if germanLocaleLink:text() == 'Deutsch'
    then
      loginPage:xpath("//input[@name='j_username']"):attr("value", "changeLocale")
      loginPage:xpath("//input[@name='j_password']"):attr("value", "de-AT")
      print('setting locale')
      loginPage = HTML(connection:request(loginPage:xpath("//input[@name='Submit']"):click()))
      print('changed locale')
  end

  loginPage:xpath("//input[@name='j_username']"):attr("value", username)
  loginPage:xpath("//input[@name='j_password']"):attr("value", password)

  local loginResponse = HTML(connection:request(loginPage:xpath("//input[@name='Submit']"):click()))
  if loginResponse:xpath("//p[@class='gErrorMessage']"):length() > 0
  then
    return LoginFailed
  end

  mcrLoginResponse = loginResponse
  -- default return is 'login ok'
end

function ListAccounts (knownAccounts)
  local ownerName = mcrLoginResponse:xpath(xPathes.accountOwner):text()
  local accountNumber = mcrLoginResponse:xpath(xPathes.accountNumber):text()
  local bankCode = mcrLoginResponse:xpath(xPathes.bankCode):text()
  local iban = mcrLoginResponse:xpath(xPathes.iban):text()
  local bic = mcrLoginResponse:xpath(xPathes.bic):text()

  -- Return array of accounts.
  local account = {
    name = "MasterCard RED",
    owner = ownerName,
    accountNumber = accountNumber,
    bankCode = bankCode,
    iban = iban,
    bic = bic,
    currency = "EUR",
    type = AccountTypeCreditCard
  }
  return {account}
end

function RefreshAccount (account, since)
  transactionRows = mcrLoginResponse:xpath(xPathes.transactionRows)

  local transactions = {}
  transactionRows:each(
    function(index, element)
      -- format: date, type, text, currency, foreign-currency-amount, exchange-rate, manipulation fees, value in EUR
      local dataFields = element:xpath('td')
      local date                  = dataFields:get(1):text()
      local transactionType       = dataFields:get(2):text()
      local text                  = dataFields:get(3):text()
      local currency              = dataFields:get(4):text()
      local foreignCurrencyAmount = dataFields:get(5):text()
      local exchangeRate          = dataFields:get(6):text()
      local manipulationFee       = dataFields:get(7):text()
      local valueInEur            = string.gsub(dataFields:get(8):text(), ',', '.')

      if transactionType ~= 'Aufladung'
        then valueInEur = -valueInEur
      end

      table.insert(transactions, {
        bookingDate = makeTimeStamp(date),
        purpose = text,
        amount = valueInEur,
        bookingText = transactionType
      })
    end
  )

  local balanceValue = string.gsub(mcrLoginResponse:xpath(xPathes.balance):text(), ',', '.')

  return {balance=tonumber(balanceValue), transactions=transactions}
end

function EndSession ()
  mcrLoginResponse = {}
end
