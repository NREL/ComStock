# ComStock Documentation

This describes how to compile the **ComStock Reference Documentation pdf** using LaTex.

## Installation

These instructions rely on the [LaTeX Workshop](https://marketplace.visualstudio.com/items?itemName=James-Yu.latex-workshop) VSCode extension.
Follow the [installation guide](https://github.com/James-Yu/LaTeX-Workshop/wiki/Install) for that extension.
LaTeX must be installed on your computer to use the extension.
The guide strongly recommends installing [TeXLive](https://www.tug.org/texlive/), which provides LaTeX distributions for both OSX and Windows.

## Compiling the ComStock Reference Documentation

1. Open `/reference_doc/main.tex`
2. `ctrl + shift + p` -> `"LaTeX Workshop: Build LaTeX project"`
3. The finished PDF and/or compiler log messages should show up in the `/reference_doc/output` directory.
    - `/output/main.pdf`: the final report PDF.
    - `/output/main.log`: the compiler output, including warnings and errors.
5. Warnings and errors can also be seen in the `PROBLEMS` tab of the VSCode Panel.
6. Output of the LaTeX compiler and LaTeX Workshop can be found in the `OUTPUT` tab of the VSCode panel.

## Directory Structure

### `/reference_doc`:

LaTeX files for the ComStock Reference Documentation

 - `/figures`: directory with figures referenced in the document
 - `/files`: directory with NREL report style definition files
 - `/tables`: directory with individual `.tex` files for each table in the document
 - `/output`: results of the compilation process
 - `main.tex`: the top level file for the document, which references others recursively
 - `chapter_section_topic.tex`: files for individual chapters and sections
 - `bibliography.bib`: references cited in the document

### `/dependency-tree-flowchart`

Files that show the relationship between ComStock input
building characteristics.
