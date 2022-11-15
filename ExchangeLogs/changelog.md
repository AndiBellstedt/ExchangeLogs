# Changelog
## 1.3.1.0 (2020-11-13)
- New: ---
- Fix:
    - Fix logging issues in command Invoke-ELCentralizeLogging
    - Fix information export issue on remembering last processed file in command Invoke-ELCentralizeLogging
- Upd: ---

## 1.3.0.1 (2020-11-18)
- No functional changes
- Fix: Fixing some typos
- Upd: Add plattform and statistic information to readme file.
## 1.3.0 (2020-09-02)
- New: Invoke-ELCentralizeLogging
    - Workflow function intendet to create a centralized logging directory to gather logfiles (supported by the module) from all exchange servers into a single directory or fileshare and withing a folder structure eligible for further processing.
    - See help for more information
- New: Invoke-ELExchangeLogConvert
    - Workflow function intendet to parse through a folder structure (staging directory, filled by Invoke-ELCentralizeLogging), find all exchange logfiles (supported by the module) and convert the files into flatten and better read-/processable CSV files.
    - See help for more information
- Fix: Get-ELExchangeLog
    - Function new can handle logs with multiple metadata lines in the conent. (service restarts or config changes can bring additional header information to W3C logfiles)

## 1.2.4 (2020-07-25)
- Fix: Get-ELExchangeLog
    - Fixing MailFrom and RcptTo extraction from smtp logs on multiple mail objects in a single session

## 1.2.3 (2020-07-19)
- Fix: Get-ELExchangeLog
    - Fixing SMTP log transform with mailsize on records with multiple mails
    - SmtpId with wrong information on smtp logs on some circumstances
    - Improved MailFrom and RcptTo extraction from smtp logs in some circumstances
- Upd: Get-ELExchangeLog
    - New property "FinalSessionStatus" on output object for smtp logs

## 1.2.1 (2020-07-11)
- Fix: Get-ELExchangeLog
    - Minor fixes on some logging circumstances were leading to errors -> Now, the function works arround this behaviour
- Upd: Get-ELExchangeLog
    - POP3 and IMAP logfiles got format data to optimize output to console with Format-List, Format-Table and Out-Gridview
    - Add alias 'gel' on command 'Get-ELExchangeLog'
- Upd: general
    - Add module logo
    - Add descriptions and a little bit of documentation

## 1.2.0 (2020-07-05)
- New: Get-ELExchangeLog
    - Add POP3 und IMAP logfile support
- Fix: Get-ELExchangeLog
    - Minor fixes on some logging circumstances were leading to errors -> Now, the function works arround this behaviour
    - Fix an issue on IPv6 address and port interpretation

## 1.1.1 (2020-06-28)
- Fix: Get-ELExchangeLog
    - Fixing internal record extraction on special cases.

## 1.1.0 (2020-06-28)
- Upd: Get-ELExchangeLog
    - Add support for importing and interpreting SMTP send log files.
    - Add more detailed fields on output records. TLS certificate informations are now separated into fields for subject, issuer, validity time, subject alternative names, ...
- Fix: Get-ELExchangeLog
    - Minor bugfixes on record processing when session in the logfile is not having all TLS information
    - Minor time and output optimizations

## 1.0.0 (2020-06-26)
- New: Frist stable version 1.0.0\
    - Get Exchange SMTP Receive Logs and output flatten record for session id's in the log files.\
    Command merge multiple logfiles together and supports "dir"/"Get-ChildItem" as Pipeline input

