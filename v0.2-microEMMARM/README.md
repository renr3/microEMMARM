# microEMMARM v0.2

This is the official repository of microEMMARM v0.2, a microcontroller-based system for performing EMM-ARM (Elastic Modulus Measurement through Ambient Response Method) tests. Previous versions can be found in the other subrepos in this same repository (_i.e._, "V0.1.b-Synercrete23" and "v..1.a-Zenodo").

The information contained here are self-sufficient for allowing full reproduction of the data-acquisition hardware necessary for performing an EMM-ARM test. It includes the data-acquisition and storage hardware and the accelerometer sensors. As an output, this system will produce a series of ".emm" files, a binary-formatted file. To post-process these files and obtain the elastic modulus evolution, check the open-source post-processing software in https://github.com/renr3/postProcess-EMMARM.

For this version v0.2, the resources available are:

1. **cases**: files to support the production of hardcases for storing the system. There are two versions available: version 1, designed primarily for manufacturing with industrial plastic but that can also be manufactured with 3D printing; version 2, designed primarily to be produced in a small 3D printer, by printing small parts of the box and assemble it later with glue.
2. **documentation**: this folder is meant to contain information relevant to understanding design and working options for the system.
3. **libraries**: the necessary Arduino libraries for the source code of the hardware system
4. **pcb**: these are all the files necessary to build the PCB (printed circuit board) of the data-acquisition system. You can find: (i) the datasheets of each of the components used in the current implementation (so you may find the exact same ones or decide on substitutions); (ii) the gerber files in case you want to order the PCB from a manufacturer like https://jlcpcb.com/; (iii) an Excel spreadsheet with the bill of materials, containing the description, quantitiy, and estimated costs and links from three online suppliers; (iv) a Fritzing file with the schematics of the system to support building over a PCB, a solderable perfboard, or a PCB; (iv) a block diagram with the parts mapping, to aid in the navigation of the project files.
5. **source**: this is the Arduino source code that you would need to upload to the microcontroller. This version was designed for the ATMega328p microcontroller, but there should be no problem in using it with similar microcontrollers.

As mentioned in the root folder, the microEMMARM project is released under the MIT license, but please check the underlying licenses on the other libraries (check **libraries** folder) to see if your intended use is somewhat restricted.
