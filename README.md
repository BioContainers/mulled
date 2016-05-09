# Mulled - Containerized Software Repository

[![Gitter](https://badges.gitter.im/mulled/mulled.svg)](https://gitter.im/mulled/mulled?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge) [![Build Status](https://travis-ci.org/mulled/mulled.svg?branch=master)](https://travis-ci.org/mulled/mulled)


# How to build your own container

  1. Open the file [packages.tsv](https://github.com/mulled/mulled/blob/master/packages.tsv) in edit mode
  2. Insert a new line describing your package you want to containerizing
    * First column is the name of your package manager [conda, linuxbrew, alpine]
    * Second column is the package name (e.g. samtools)
    * Third column is the package version (e.g. 1.3--1). The version format depends on your package manager please have a look at other examples to get it right.
  3. Create a Pull Request and wait until our testing passes
  4. You are done. We will merge your PR as early as possible or you can apply to get commit access by asking on [gitter](https://gitter.im/mulled/mulled?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)




## Conceptual Overview

![Flowchar](pictures/mulledflow.png)
