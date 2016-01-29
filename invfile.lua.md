---
papersize: a4paper
classoption: draft
documentclass: article
title: Mulled
subtitle: Containerized Packages in the Cloud
author:
  - Jonas Weber
  - Björn Grüning
---

# Introduction

Docker©[^docker-trademark] provides a way to containerize
applications in portable images that contain all dependencies needed to use the
program. Determining the dependencies (libraries, interpreters etc.) is however
a non-trivial task, as there is no standardized way for developers to specify
them.

Package managers such as Conda or Homebrew were established out of this need,
providing a huge number of package descriptions that list the steps needed to
build the software and the dependencies it needs. Packages can then be
installed from those repositories, provided that relevant compilers and tools
are present on the host system.

Mulled fetches build instructions from such package managers, and compiles
applications ahead-of-time in the cloud. Resulting images are made available
in public image repositories.

-- TODO
The remainder of this article is structured as follows: Firstly, we introduce
the builders (one for each enabled package manager). After that, we describe
how the build system determines which packages need to be rebuilt.

This article is written in a special way: The article is written in Markdown,
and the code samples shown throughout the article constitute the complete
source code for the software.

# Architecture

Mulled takes build instructions from a package definitions file
(`packages.tsv`) and builds them according to the rules specific to each
packager encoded in this file. The results are stored in a Quay.io repository.

Each time a commit is done in the GitHub repository a Travis CI executes this
file. All packages that need rebuilding (i.e. that have no matching version
already built and packaged) are built and tested. If the commit is on `master`,
the result is pushed to Quay.io and stored.

Mulled uses Involucro[^involucro] to execute Docker containers and wrap
directories into images. This file as a whole is a (albeit complex) build
script that controls Involucro.

Each of the builders executes a number of Docker containers with a build directory
mounted into it. Each container modifies this directory to some extent, and the final
result is a directory containing exactly the files that should end up in the Docker image.
Involucro then reads this directory and puts it on top of an existing base image, such
as `busybox`.

# Preliminary Steps

Firstly, we define some settings. These name utility images used later:

    curl = 'appropriate/curl:3.1'
    jq = 'local_tools/jq'
    git = 'local_tools/git'
    busybox = 'busybox:latest'

We also determine where the results will be stored:

    quay_prefix = 'mulled'
    namespace = 'quay.io/' .. quay_prefix
    github_repo = 'mulled/api'

    current_build_id =
      'https://travis-ci.org/mulled/mulled/builds/'
      .. ENV.TRAVIS_BUILD_ID

The Lua version used in Involucro doesn't provide native support for splitting
a `string` by a delimiter. This utility function fills that gap:

    function split(s, delim)
      local start = 1
      local t = {}
      while true do
        local pos = string.find(s, delim, start, true)
        if not pos then break end
        table.insert(t, string.sub(s, start, pos - 1))
        start = pos + #delim
      end
      table.insert(t, string.sub(s, start))
      return t
    end

    assert(table.concat(split("a-d", "-"), "/")   == "a/d")
    assert(table.concat(split("a..d", ".."), "/") == "a/d")



# Builders

Builders are functions that get a package specification and create tasks of the
form `type:package`, where `type` is one of `build`, `test` and `clean`.  These
builders are stored in a Lua table, appropriately called `builders`:

    builders = {}

The key names from this table reappear in the `packages.tsv` file in the
left-most column.

## Alpine

Alpine Linux[^alpine-linux] is 'a security-oriented, lightweight Linux
distribution based on musl libc and busybox' (from their homepage). Packages
are provided in binary format, compiled with the `musl libc` (instead of the
more common `glibc`).

    builders.alpine = function (package, revision, test, builddir)
      local repo = namespace .. '/' .. package .. ':' .. revision

### Building a package

Alpine provides a tool called `apk` that manages installation of packages. The
options set in the command below install the package into the directory
`/data/dist`, after updating the cache from the given URL, but using the keys
from the 'host' installation. Otherwise, the repository signatures wouldn't be
checkable.

      local install = 'apk --root /data/dist'
      .. ' --update-cache --repository '
      .. ' http://dl-4.alpinelinux.org/alpine/latest-stable/main'
      .. ' --repository '
      .. ' http://dl-4.alpinelinux.org/alpine/latest-stable/community'
      .. ' --keys-dir /etc/apk/keys --initdb add '

After installation we have to extract some information from the package
manager, namely the installed version, a description and the upstream homepage.
We can get the information from `apk` with `apkg info`, again specifying the
root of our installation.  `-wd` causes `apk` to print the web page and
description of the package.

Unfortunately, the format `apk` provides is not ideal for programmatic consumption.
Using `-wd` we get the following:

```
musl-1.1.11-r2 description:
the musl c library (libc) implementation

musl-1.1.11-r2 webpage:
http://www.musl-libc.org/
```

A POSIX shell allows consuming the same input stream with multiple tools by
combining them with parentheses. The `read` tool reads one line and assigns it
to the environment variable named by it's parameter. We assume the following:
In the second line we can find the package name followed by version and release
counter, in the third line follows the description, and in the sixth the
homepage:

    local extractInfo = 'apk info --root /data/dist -wd  ' .. package 
      .. ' | ( read fline ;'
      .. ' echo $fline | cut -d" " -f1 |'
      .. '   cut -d"-" -f 2-3 > /data/info/version; '
      .. ' read desc; echo  $desc > /data/info/description ; '
      .. ' read discard ; '
      .. ' read discard ; '
      .. ' read homepage ; echo $homepage > /data/info/homepage ;'
      .. ')'

The actual build step uses `alpine:latest` with a shell as entry point and the
build directory (which was received as parameter to this function) mounted at `/data`:

      inv.task('build:' .. package .. ':' .. revision)
        .using('alpine:latest')
          .withConfig({entrypoint = {"/bin/sh", "-c"}})
          .withHostConfig({binds = {builddir .. ':/data'}})

In  the build directory we need a `dist` directory, being the root directory for the new
image, and an `info` directory containing files describing metadata about the image.

          .run('mkdir -p /data/dist /data/info')

Afterwards, we register a step that installs the package and extracts information using
the commands defined above.

          .run(install .. package .. ' && ' .. extractInfo)

To decrease the size of the resulting image we can remove the result of repository update
from before.

          .run('rm -rf /data/dist/lib/apk /data/dist/var/cache/apk/')

Finally, we take the `dist` directory and package it as a layer on top of the latest `busybox`
image (based on musl libc).

          .wrap(builddir .. '/dist').at('/')
            .inImage('busybox:latest').as(repo)

### Testing

Each package should specify a test in `packages.tsv`. This is executed in the
resulting image to make sure that the program works as intended and is not
missing necessary libraries.

Execution failure is indicated in Unix system with an exit code different from
zero. Involucro automatically catches that and breaks the build system, if the
test fails.

      inv.task('test:' .. package .. ':' .. revision)
        .using(repo)
        .withConfig({entrypoint = {'/bin/sh', '-c'}})
        .run(test)

### Cleaning up

Finally, after testing and optionally pushing the image to the repository the
generated files should be removed, to make room for the next package.

      inv.task('clean:' .. package .. ':' .. revision)
        .using('alpine:latest')
          .withHostConfig({binds = {builddir .. ':/data'}})
          .run('rm', '-rf', '/data/dist', '/data/info')

    end

## Conda

Conda[^conda] is 'an open source package management system [...]' (from their homepage).
It was originally built for Python, but can handle any type of package.
By default, it uses the Anaconda Software Repository, but anyone can create custom 'channels'
to distribute their software.

    builders.conda = function (package, revision, test, builddir)
      local repo = namespace .. '/' .. package .. ':' .. revision

In this implementation, the enabled channels are `bioconda` and `r`.

      local channels = {
        "bioconda", "r"
      }
      local channelArgs = ""
      for i, c in pairs(channels) do
        channelArgs = channelArgs .. "--channel " .. c .. " "
      end

Conda heavily relies on paths that have to be exactly the same in the building and in the
final image. Additionally, it relies on the environment variable `$PATH` to find executables.
The simplest way to ensure both is to install the packages to `/usr/local`, so executables end
up in `/usr/local/bin`, which is in `$PATH` by default.

The metadata directory is mounted separately to `/info`.

      local condaBinds = {
        builddir .. "/info:/info",
        builddir .. "/dist:/usr/local",
      }

The default directory for installation can be overridden with the `-p`
parameter.  It is also necessary to pass `--copy` to forbid Conda from only
linking the files into the destination directory, and `--yes` to force
unattended installation. The enabled channels are passed in as well.

      local install = 'conda install ' .. channelArgs ..
        ' -p /usr/local --copy --yes '

Metadata for Conda packages is stored in JSON files in
`/opt/conda/pkgs/` `<package-version-build>/` `info/recipe.json`.  Since the version
and build is given in a slightly different format (version--build) in the
`packages.tsv`, we have to convert it first:

      local packageDirName = package .. '-' ..
        table.concat(split(revision, "--"), "-")

Extracting the info is as simple as copying the `recipe.json` file into the `/info` directory that is available
to other build steps.

      local extractInfo = 'cp /opt/conda/pkgs/' .. packageDirName
        .. '/info/recipe.json /info/raw.json'

This raw information file is not practical to use in further steps, so we have
to read the interesting values and write them into specific files. The tool
`jq` can be used to transform JSON files. Usually, it outputs JSON again, but
by passing `--raw-output` it just prints the textual content of the last
result.

A program in `jq` is a sequence of filters, each consuming the result of the
preceding (or the input file, if it is the left most filter).  The given
program reads the three desired values, and places them in an array.
Afterwards, the elements of this array are joined by line breaks. This result
is then consumed by two `read` invocations, similar to above. The version value
is set using the revision from the `packages.tsv`.

      local transformInfo = '/jq-linux64 --raw-output '
        .. [==[ '[.about.home, .about.summary] ]==] 
        .. [==[ | join("\n")' /info/raw.json | ( ]==]
        .. ' read homepage ; echo $homepage > /info/homepage ; '
        .. ' read desc ; echo $desc > /info/description ; '
        .. ' echo ' .. revision .. [==[ > /info/version ) ]==]

The revision value in `packages.tsv` is used to name the tag of the
corresponding Docker image, which disallows the use of `=`. However, Conda uses
an equal sign to separate version code and build number. As a solution we propose
using a double dash (`--`) instead in the `packages.tsv`, which can then be translated
into an equal sign when communicating with Conda.

      local conda_version = table.concat(split(revision, "--"), "=")

The actual build step utilizes the official `miniconda` image from Continuum Analytics
with a default shell. It executes the install and extract information commands.
Afterwards, with the help of the `jq` utility image, this information is transformed,
and the final image is generated by wrapping the `dist` directory on top of
`progrium/busybox` (a glibc-based build).

      inv.task('build:' .. package .. ':' .. revision)
      .using('continuumio/miniconda:latest')
        .withConfig({entrypoint = {"/bin/sh", "-c"}})
        .withHostConfig({binds = condaBinds})
        .run(install .. package .. '=' .. conda_version
          .. ' && ' .. extractInfo)
      .using(jq)
        .withHostConfig({binds = condaBinds})
        .run(transformInfo)
      .wrap(builddir .. '/dist').at('/usr/local')
        .inImage('progrium/busybox:latest')
        .as(repo)

### Cleaning up

For Conda, clean up consists of removing the destination and information directories.

      inv.task('clean:' .. package .. ':' .. revision)
        .using('continuumio/miniconda:latest')
          .withConfig({entrypoint = {"/bin/sh", "-c"}})
          .withHostConfig({binds = {builddir .. ':/data'}})
          .run('rm -rf /data/dist /data/info')

### Testing

The test in the last column is executed in the resulting image.

      inv.task('test:' .. package .. ':' .. revision)
        .using(repo)
        .withConfig({entrypoint = {'/bin/sh', '-c'}})
        .run(test)
    end

## Linuxbrew

Linuxbrew is a fork of Homebrew[^homebrew] with the focus on Linux packages. It provides
'formulas' that describe how to fetch and compile software packages, and installs them
on the system.

    builders.linuxbrew = function (package, revision, test, builddir)
      repo = namespace .. '/' .. package .. ':' .. revision

### Building a package

Brew requires an external builder image. TODO

After the installation, metadata about the package has to be extracted.
Luckily, `brew info` provides a JSON interface that outputs the desired
information as a JSON array. Again, `jq` is used to select the fields, send
them via a pipe where they are read and stored in files:

      extractInfo = '$BREW info --json=v1 ' .. package
        .. [==[ | jq --raw-output '.[0] | ]==]
        .. '[.homepage, .desc, .versions.stable] | join("\n")'
        .. [==[ ' | ( ]==]
          .. 'read homepage ; echo $homepage > /info/homepage ; '
          .. 'read desc ; echo $desc > /info/description ; '
          .. 'read version ; echo $version > /info/version ; '
        .. ')'

The actual build step firstly creates the output directories, and transfers
ownership to `nobody`. This is necessary since the builder has to be run as
`nobody`, but the output directory is only writeable by `root`.

      inv.task('build:' .. package .. ':' .. revision)
        .using('local_tools/linuxbrew_builder')
          .withConfig({user = "root"})
          .withHostConfig({binds = {builddir .. ':/data'}})
            .run('mkdir', '-p', '/data/info', '/data/dist')
            .run('chown', 'nobody', '/data/info', '/data/dist/')

*Inside* the output directory more subdirectories are created, that will contain
the output files.

          .withConfig({user = "nobody"})
            .run('mkdir', '/data/dist/bin', '/data/dist/Cellar')


          .withConfig({
            user = "nobody",
            entrypoint = {"/bin/sh", "-c"},
            env = {
              "BREW=/brew/orig_bin/brew",
              "HOME=/tmp"
            }
          })
          .withHostConfig({binds = {
            builddir .. "/dist/bin:/brew/bin",
            builddir .. "/dist/Cellar:/brew/Cellar",
            builddir .. "/info:/info"
          }})
          .run('$BREW install ' .. package)
          .run('$BREW test ' .. package)
          .run(extractInfo)

        .wrap(builddir .. '/dist').inImage('mwcampbell/muslbase-runtime:latest')
          .at("/brew/").as(repo)

### Cleaning up

This step removes all files generated during the run. It is run as the user `root`:

      inv.task('clean:' .. package .. ':' .. revision)
      .using('local_tools/linuxbrew_builder')
        .withConfig({user = "root"})
        .withHostConfig({binds = {builddir .. ':/data'}})
        .run('rm', '-rf', '/data/dist', '/data/info')

### Testing

Testing is similar to the other builders. The provided test is executed with a
shell and the exit code is automatically checked.

      inv.task('test:' .. package .. ':' .. revision)
        .using(repo)
        .withConfig({entrypoint = {'/bin/sh', '-c'}})
        .run(test)
    end

# Pushing Tasks

The *push* task is shared among the builders. It is provided as a function that
creates the task according to the given values. The name of the task is
`push:<package_name>`.

    function pushTask(package, new_revision, packager, builddir)
      local repo = namespace .. '/' .. package .. ':' .. new_revision

      inv.task('push:' .. package .. ':' .. new_revision)

Quay automatically creates a repository when pushed to. But, at least at the
time of writing, this repository is private by default. To have full control
over the creation we try to explicitly create it each time and just ignore any
failures.

The object that is passed to Quay.io is of the following form:

```json
{
  "namespace": "mulled",
  "visibility": "public",
  "repository": "<package_name>",
  "description": ""
}
```

This object is built in the step below. At the end, we safeguard against
failure with `|| true`.

        .using(curl)
          .withConfig({env = {"TOKEN=" .. ENV.TOKEN}})
          .run('/bin/sh',  '-c', 'curl --fail -X POST '
              .. '-HAuthorization:Bearer\\ $TOKEN '
              .. '-HContent-Type:application/json '
              .. '-d \'{"namespace": "' .. quay_prefix .. '",'
              .. '"visibility": "public", '
              .. '"repository": "' .. package .. '",'
              .. '"description": ""}\' '
              .. 'https://quay.io/api/v1/repository || true')

Using the official image `docker` image we can now push the images to the
repository. The socket for the Docker instance on the host is mounted into the
container, as well as the configuration directory.  The latter is needed to
authenticate ourselves against Quay.io.

        .using('docker:latest')
          .withHostConfig({
            binds = {
              "/var/run/docker.sock:/var/run/docker.sock",
              ENV.HOME .. "/.docker:/root/.docker",
              builddir .. ':/pkg'
            }
          })
          .run('/bin/sh', '-c', 
            'docker push ' .. repo)
          .run('/bin/sh', '-c',
            'docker inspect -f "{{.VirtualSize}}" ' .. repo
              .. ' > /pkg/info/size')

The description of the Quay.io repository for this package contains a description
and an upstream link. This is always generated by the last revision to be pushed there,
since it's only possible to have one description. It is then shared for all tags.

        .using(jq)
          .withHostConfig({binds = {
            builddir .. ':/pkg',
            './data:/data'
          }})
          .run('('
            .. 'echo "# ' .. package .. '" ; echo; '
            .. 'echo -n "> "; cat /pkg/info/description; echo; '
            .. 'cat /pkg/info/homepage; '
            .. 'echo ) | /jq-linux64 --raw-input --slurp \'{description: .}\' > /pkg/info/quay_description')

        .using(curl)
          .withHostConfig({binds = {builddir .. ':/pkg'}})
          .withConfig({env = {"TOKEN=" .. ENV.TOKEN}})
          .run('/bin/sh', '-c', 'curl --fail -HAuthorization:Bearer\\ $TOKEN -T /pkg/info/quay_description  '
              .. '-HContent-type:application/json '
              .. 'https://quay.io/api/v1/repository/' .. quay_prefix .. '/' .. package)

The last step for this package is the generation of the API database entry.
All the small information files that were prepared in the previous step are
read in order and inserted into the correct location by `jq`. Each file
contains one line, and the combination of `--raw-input` and `--slurp` makes
`jq` convert this to a big string, with newlines as separators.  This array is
split and indexed with positional indexes.

Similar to the Quay.io repository description, the description and homepage are
taken from the latest revision.

However, we have to make sure that the file containing 'old' revisions exists in
the package information directory. If any old revisions exist, they are copied over,
otherwise a new array is used.

    .using(busybox)
      .withHostConfig({binds = {
        builddir .. ':/pkg',
        './data:/data'
      }})
      .run('/bin/sh', '-c',
        'cp /data/api/_images/' .. package .. '.json'
        .. ' /pkg/info/github.json '
        .. '|| echo "{}" > /pkg/info/github.json')

    .using(jq)
      .withHostConfig({binds = {
        builddir .. ':/pkg',
        "./data:/data"
      }})
      .run('/jq-linux64 --raw-output --raw-input --slurp \'.|split("\n") as $i'
        .. '| ("---\n---\n" + ({'
          .. 'image: "' .. package .. '",'
          .. 'packager: "' .. packager .. '", '
          .. 'homepage: $i[0], description: $i[1], '
          .. 'versions: ($i[3] | fromjson | (.versions // []) | '
          .. '  map(select(.revision != "' .. new_revision
          .. '" )) + [{version: $i[2], revision: "' .. new_revision
          .. '", size: $i[4], date: (now | todate)}]),'
          .. 'buildurl: "' .. current_build_id .. '"}'
          .. '|tostring))\''
          .. ' /pkg/info/homepage /pkg/info/description '
          .. '/pkg/info/version /pkg/info/github.json  /pkg/info/size '
          .. ' > /data/api/_images/' .. package .. '.json')
    end

# The Build Tasks

## packages.tsv

The `packages.tsv` contains all information needed to build images. It is a Tab
Separated Values file containing columns denoting the packager, the package
name, a revision identifier and a test.  All five fields are mandatory, but the
last field can be set to `true` to turn off tests.

As the first step in this tool, we read and parse this definitions file. During parsing, the steps for each
package are generated using the builders.

    local firstLine = true
    for line in io.lines("packages.tsv") do
      if not firstLine then
        local fields = split(line, "\t")
        local packager = fields[1]
        local package = fields[2]
        local revision = fields[3]
        local test = fields[4]
        local builddir = "./mulled-build-" .. package

        builders[packager](package, revision, test, builddir)
        pushTask(package, revision, packager, builddir)
      end
      firstLine = false
    end

## Overall tasks

The tool can be used in two modes: In local test mode and in deploy mode.
Usually, local test mode is used when evaluating the compilability of pull
requests, while deploy mode is reserved for commits on `master`. Appropriately,
we define two tasks called `test` and `deploy`.

    test = inv.task('test')
    deploy = inv.task('deploy')

After the preparatory steps have completed, we will read in the build list and
attach all predefined, package specific tasks to the overall tasks:

    function afterPrepare()
      for package in io.lines("data/build_list") do
        if package ~= "" then
         test
            .runTask('build:' .. package)
            .runTask('test:' .. package)
            .runTask('clean:' .. package)

          deploy
            .runTask('build:' .. package)
            .runTask('test:' .. package)
            .runTask('push:' .. package)
            .runTask('clean:' .. package)
        end
      end
      deploy
        .runTask('main:commit_api_database')
    end

# Determining What To Build

It is highly inefficient to build every single package every time a build is
invoked. In this tool, we restrict ourselves to building packages in versions
that are not already registered in our API database.

Firstly, we fetch the current API 'database' from GitHub. This database is
comprised of several JSON files containing common and revision specific
information for each package. Each file may look like the following example
(note the YAML frontmatter for Jekyll):

```json
---
---
{
 "image": "bc",
 "packager": "alpine",
 "homepage": "http://www.gnu.org/software/bc/bc.html",
 "description": "An arbitrary precision numeric processing language (calculator)",
 "versions": [
   {
   "revision": "1",
   "version": "1.06.95-r2",
   "size": 5000,
   "date": "2016-01-26T11:00:02Z",
   "buildurl": "https://travis.ci-org./mulled/mulled/builds/203830"
   },
   {
   "revision": "2",
   "version": "1.06.95-r3",
   "size": 4000,
   "date": "2016-01-26T11:02:02Z",
   "buildurl": "https://travis.ci-org./mulled/mulled/builds/203831"
  }
 ]
}
```

We clone the repository into a subdirectory called `data/api`:

    inv.task('main:versions:clone_from_github')
      .using(git)
        .run('clone', 'https://github.com/mulled/api.git', 'data/api')

These data files still contain the YAML frontmatter, and have to be transformed
to make easy use of them in later steps. A `jq` program is used to read them in,
and store a single JSON object assinging a list of versions to each package.

    local parseGithubImages = 'map({(.image): (.versions | map(.revision))}) | add // {}'

    inv.task('main:versions:process_versions_from_github')
      .using(busybox)
        .run('/bin/sh', '-c', 'tail -q -n +3 data/api/_images/*json > data/github_jsons.jsonl || touch data/github_jsons.jsonl')
      .using(jq)
        .run('/jq-linux64 --slurp \'' .. parseGithubImages .. '\' data/github_jsons.jsonl > data/github_versions')

As the next step, we parse the list of locally defined packages and intersect
this with the list of remotely available images. The `packages.tsv` is split
into lines (removing the first one), and each of those lines is split into
fields. The data contained there is output in JSON format, similar to the
format of the query above.

    parsePackages = 'split("\n")[1:] |'
      .. 'map(select((. | length) > 0)) |'
      .. 'map(split("\t")) |'
      .. 'group_by(.[1]) |'
      .. 'map({(.[0][1]): map(.[2])}) | add'

    inv.task('main:versions:load_from_packages.tsv')
      .using(jq).run('/jq-linux64 --slurp --raw-input \'' .. parsePackages
        .. '\' packages.tsv > data/local_versions')

The build list is a simple file with each package / revision combination taking
exactly one line.

    computeBuildList = 'map(to_entries |'
      .. 'map(.key as $k | .value | map($k + ":" + .))'
      .. '| flatten) | .[1] - .[0] | join("\n")'

    inv.task('main:generate_list:builds')
      .using(jq).run('/jq-linux64 --slurp --raw-output \''
        .. computeBuildList .. '\' data/github_versions data/local_versions'
          .. ' > data/build_list')

The data directory will contain all data concerning the whole build process.

    inv.task('main:create_data_dir')
      .using(busybox)
        .run('mkdir', '-p', 'data')

It is not possible to have the same package identifier with the same revision
occurring multiple times in the same `packages.tsv`. This check tests for any
duplicates and tells the user.

    inv.task('main:check_uniqueness_of_keys')
      .using(busybox)
        .run('/bin/sh', '-c',
          -- fields 2 and 3 are package name and revision
          "cat packages.tsv | cut -f2-3 |"
          .. "sort | uniq -d |" -- filter out non-duplicates
          .. "wc -l | xargs -I%% test 0 -eq %% ||"
          .. "(echo 'Package not unique' 1>&2 && false)")

    inv.task('main:prepare')
      .runTask('main:check_uniqueness_of_keys')

      .runTask('main:versions:clone_from_github')
      .runTask('main:versions:process_versions_from_github')

      .runTask('main:versions:load_from_packages.tsv')

      .runTask('main:generate_list:builds')
      .runTask('main:after_prepare')

    inv.task('main:after_prepare')
      .hook(afterPrepare)

# Final Steps

If we are doing a production build on Travis, we have to commit/push the new
API database.

    inv.task('main:commit_api_database')
      .using(git)
        .withHostConfig({
          binds = {
            "./data/git/.gitconfig:/root/.gitconfig",
            "./data/netrc:/root/.netrc",
            "./data/api:/source"
          }})
        .run('add', '_images')
        .run('commit', '-m', 'Build ' .. ENV.TRAVIS_BUILD_NUMBER)
        .run('push', 'origin', 'gh-pages')

# Appendix

Some utility tasks are needed. They are defined here.

## local_tools/jq

Quite often in this tool, a generic image containing `jq` is needed. This image
is generated as follows:

    inv.task('main:generate_image:jq')
      .using(busybox)
        .run('mkdir', '-p', 'jq')
      .using(curl)
        .run('--location',
          'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64',
          '-o', 'jq/jq-linux64')
      .using(busybox)
        .run('chmod', 'a+x', 'jq/jq-linux64')
      .wrap('jq').at('/')
        .withConfig({entrypoint = {'/bin/sh', '-c'}})
        .inImage(busybox).as(jq)
      .using(busybox)
        .run('rm', '-rf', 'jq')

## local_tools/git

This image contains the `git` client:

    inv.task('main:generate_image:git')
      .using('alpine:latest')
        .run('mkdir', '-p', 'alpine-git')
        .run('apk', '--root', '/source/alpine-git',
          '--update-cache', '--repository',
          'http://dl-4.alpinelinux.org/alpine/latest-stable/main',
          '--keys-dir', '/etc/apk/keys', '--initdb', 'add',
          'git')
        .run('rm', '-rf', 'alpine-git/lib/apk', 'alpine-git/var/cache/apk/')
      .wrap('alpine-git').at('/').withConfig({
          entrypoint = {'/usr/bin/git'}
        }).inImage('alpine:latest').as(git)
      .using('alpine:latest')
        .run('rm', '-rf', 'alpine-git')

## local_tools/linuxbrew_builder

The builder image for `linuxbrew` is generated here. It contains everything
Linuxbrew expects from the compiling host.

    inv.task('main:generate_image:linuxbrew_builder')
      .using('alpine:latest')
        .run('mkdir', '-p', 'linuxbrew-alpine/brew', 'linuxbrew-alpine/tmp')
        .run('apk', '--root', '/source/linuxbrew-alpine',
          '--update-cache', '--repository',
          'http://dl-4.alpinelinux.org/alpine/latest-stable/main',
          '--keys-dir', '/etc/apk/keys', '--initdb', 'add',
          'git', 'make', 'clang', 'ruby', 'ruby-irb', 'ncurses-dev',
          'tar', 'binutils', 'build-base', 'bash', 'perl',
          'zlib', 'zlib-dev', 'jq', 'patch')

      .using(git)
          .run('clone', 'https://github.com/Homebrew/linuxbrew', 'linuxbrew-alpine/brew')
      .using('alpine:latest')
        .run('cp', '-r', 'linuxbrew-alpine/brew/bin', 'linuxbrew-alpine/brew/orig_bin')
        .run('/bin/sh', '-c',
          'find linuxbrew-alpine/brew -print0 | xargs -0 -n 1 chown nobody:users')
        .run('chown', 'nobody:users', 'linuxbrew-alpine/brew', 'linuxbrew-alpine/tmp')
        .run('rm', '-rf', 'linuxbrew-alpine/lib/apk', 'linuxbrew-alpine/var/cache/apk/')
      .wrap('linuxbrew-alpine').inImage('alpine:latest')
        .at('/').as('local_tools/linuxbrew_builder')

      .using('alpine:latest')
        .run('rm', '-rf', 'linuxbrew-alpine')

## Article

This article can build itself, and the task to do that is defined here. It
is using `pandoc` to transform the Markdown source into LaTeX, which is then
compiled into PDF with `xelatex`.

    inv.task('article')
      .using('thriqon/full-pandoc:latest')
        .run('pandoc',
          '--standalone',
          '--toc',
          '--toc-depth=2',
          '--indented-code-classes=lua',
          '--highlight-style=pygments',
          '-o', 'mulled.tex',
          '-i', 'invfile.lua.md')
      .using('thriqon/xelatex-docker:latest')
        .run('xelatex', 'mulled.tex')

## Travis CI Build

If this tool is executed in Travis CI, it provides meaningful step to execute
there. These are grouped under the task `travis`.

    local travis = inv.task('travis')

We always have to rebuild the local tools, since they are not available in a
repository:

    travis
      .runTask('main:create_data_dir')
      .runTask('main:generate_image:jq')
      .runTask('main:generate_image:git')
      .runTask('main:generate_image:linuxbrew_builder')

The branch currently being tested is stored in the environment variable
`TRAVIS_BRANCH`, but this is also set to `master` when testing a pull request
directed at `master`.  We therefore have to make sure that this is actually a
production build by testing for target branch and pull-requestness. If secure
environment variables are available, i.e. this is a build originated from the
official mulled repository and not a fork, we also generate a trusted `.netrc`
to make `git` authenticate with GitHub.  Before actually testing or deploying
the packages, the build environment has to be prepared:

    if ENV.TRAVIS_SECURE_ENV_VARS == "true" then
      travis.runTask('main:netrc:trusted')
    else
      travis.runTask('main:netrc:plain')
    end
    travis.runTask('main:configure_git')

    travis
      .runTask('main:prepare')

    if ENV.TRAVIS_PULL_REQUEST == "false" and ENV.TRAVIS_BRANCH == "master" then
      travis
        .runTask('deploy')
    else
      travis
        .runTask('test')
    end

    inv.task('main:netrc:trusted')
      .using(busybox)
        .withConfig({env = {"TOKEN=" .. ENV.GITHUB_TOKEN}})
        .run('/bin/sh', '-c', 'echo "machine github.com login $TOKEN" > data/netrc')
        .run('chmod', '0600', 'data/netrc')

    inv.task('main:netrc:plain')
      .using(busybox)
        .run('/bin/sh', '-c', 'echo "machine github.com login mulled_bot" > data/netrc')
        .run('chmod', '0600', 'data/netrc')

    inv.task('main:configure_git')
      .using(git)
        .withHostConfig({binds = {
          "./data/git:/root/"
        }})
        .run('config', '--global', 'user.name', 'MulledBot')
        .run('config', '--global', 'user.email', 'mulled@bot.com')
        .run('config', '--global', 'push.default', 'simple')

[^alpine-linux]: <http://www.alpinelinux.org/>
[^docker-trademark]: Docker is a registered trademark of Docker, Inc.
[^involucro]: <https://github.com/thriqon/involucro>
[^conda]:   <http://conda.pydata.org/docs/>
[^homebrew]: <http://brew.sh>
[^github-create-a-file]: <https://developer.github.com/v3/repos/contents/#create-a-file>
