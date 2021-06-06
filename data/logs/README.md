# Introduction

The purpose of logs, is to gather information about options of different scanners.

# How to use it

If you would like to check minimum and maximum values of the `brightness`, you could type:
```
$ cd data/descriptors
$ git grep name=\'brightness\'
```
The output of this command will be for example:
```
Canon_LiDE_220.log:[+5,91s] DEBUG: scanner.vala:735: Option 24: name='brightness' title='Brightness' type=int size=4 min=-100, max=100, quant=1 cap=soft-select,soft-detect
Epson_NX300.log:[+58,31s] DEBUG: Option 6: name='brightness' title='Brightness' type=int size=4 min=0, max=0, quant=0 cap=soft-select,soft-detect,inactive
Hewlett-Packard_Officejet_4630_series.log:[+10,75s] DEBUG: scanner.vala:742: Option 6: name='brightness' title='Brightness' type=int size=4 min=0, max=2000, quant=0 cap=soft-select,soft-detect,advanced
````

The first word is the file name (eg. `Canon_LiDE_220.log`), which corresponding to Scanner/Printer model.
You could notice that for `Canon_LiDE_220` the `brightness` range is `-100,100`,
for `Epson_NX300` it is `0,0`, as the descriptor is inactive and for `HP_4630` the range is `0,2000`.

# How to add new logs

1. Run simple scan in debug mode:
   ```
   $ simple-scan --debug
   ```

1. Press scan button

1. Create new `.log` file

1. Copy logs from terminal to a new file

1. Create Merge Request
