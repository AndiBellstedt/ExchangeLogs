# Changelog
## 1.2.1 (2020-07-11)
- Fix: Get-ELExchangeLog
    - Minor fixes on some logging circumstances were leading to errors -> Now, the function works arround this behaviour
- Upd: Get-ELExchangeLog
    - POP3 and IMAP logfiles got format data to optimize output to console with Format-List, Format-Table and Out-Gridview
    - Add alias 'gel' on command 'Get-ELExchangeLog'
- Upd: general
    - add module logo
    - add descriptions and a little bit of documentation

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
    - minor bugfixes on record processing when session in the logfile is not having all TLS information
    - minor time and output optimizations

## 1.0.0 (2020-06-26)
- New: Frist stable version 1.0.0\
    - Get Exchange SMTP Receive Logs and output flatten record for session id's in the log files.\
    Command merge multiple logfiles together and supports "dir"/"Get-ChildItem" as Pipeline input

