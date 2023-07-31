# pingHermes
A utility to check if a PC is alive, using **ping**

## Table of Contents
<!-- vim-markdown-toc Marked -->

<!-- vim-markdown-toc -->

## Intro

Having a remote PC running unattended is always a point of worry for any administrator.

To counter this, here comes a utility that will **ping** any PC (given its IP), and report back its state, providing both a visual and a audio report.

The program is called **pingHermes** (from the hostname of the first system this application was tested on).

When executed, it will remain in the system tray and silently ping the target PC, until it does not get a ping reply. Then, it will show its window and start playing an alarm sound.


![pingHermes](pingHermes.jpg)

## Installation

The program comes in the form of an executable file (EXE on Windows), which is all that's necessary for its execution.

Just place the executable file in a directory and execute it; all needed files are contained within the executable and will be extracted as needed.

Then, just click on its system icon and select **Help** to get more info about the way to configure it.


## Building from source

### Other platforms

Although this project is supposed to be used on Windows, it can be compiled and used under Linux, MacOS and the BSDs.


