
# Contributing to Mulled

There are several ways to contribute to this software repository. Help is
always welcome :)

## Using / Giving Feedback

Often forgotten, but by merely using (and optionally giving feedback) is one of
the best ways to validate our work. If anything is not up to your expectations
or if you have any wishes, please feel free to [open an issue on
GitHub](https://github.com/mulled/mulled/issues/new) or on
[Gitter](https://gitter.im/mulled/mulled).

## Proposing Packages

New packages can be added by inserting a new line into the `packages.tsv` file in this
repository. It's a Tab Separated Values file with the following fields:

* Packager: One of the available packagers (`linuxbrew`, `alpine`, `conda`).
* Package: The name of the package as it is installable from the builder. This
    name must be unique in the whole file.
* Revision: Apart from the `conda` packager, this is a simple integer that is
    incremented when a rebuild is needed. `conda` packages can be installed
    directly using their version identifier. Please note that for technical
    reasons the build number is separated using a double dash (--) instead of
    an equal sign (=).
* Test: A small shell script that is executed in the context of the new
    container to check whether the build was actually successful. If possible,
    this should check the actual working of the program, but a test for
    `--version` is also okay.

### Three steps to a package

1. Find a package you want to add, for example you can search for it in one of
   the repositories that are supported:
  - [Conda](https://conda.anaconda.org/)
  - [Braumeister](https://braumeister.org)
  - [Alpine Packages](https://alpine-linux.org/packages/)
2. Edit the `packages.tsv` and send a Pull Request. As soon as the build
   succeeds and the package has been approved, it will be added to the
   repository.
3. Run the image: `docker run quay.io/mulled/...`

### Slightly Longer Version

You can follow the following steps to add a new package (we assume that the `hello` package is not yet available):

0. Check pull requests in this repository, somebody might already be in the
   process of proposing this package. Make sure that the name doesn't already
   occur in `packages.tsv`.
1. Choose the package manager. This is highly subjective, and quite often
   people just choose the one they already know. In this case, we're going with
   `linuxbrew`.
2. Set the version. As this is not the `conda` builder, we simply choose "1".
3. Determine a useful test. In the case of the 'hello world' program this might
   be checking if the output is actually 'hello world'.
4. Open the [packages.tsv on
   master](https://github.com/mulled/mulled/blob/master/packages.tsv) and click
   the 'edit' button (see [Editing
   files](https://help.github.com/articles/editing-files-in-another-user-s-repository/)).
   GitHub will fork the repository in the background, and you can start editing
   the file. By default the spacing mode is set to 'Spaces', but we need 'Tabs'
   here. Please change that in toolbar.
5. Start a new line with the fields. Do not modify any other lines, this would
   complicate the process.
6. Click 'Propose file change' and create the pull request.

That's it! We will review and if possible include the package into the repository.

## Write Integration

You are welcome to develop a new builder as well. Describing this process is too much
for this guide, however. Please read the `infile.lua.md` for details.


