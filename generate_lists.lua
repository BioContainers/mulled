
-- Settings

curl = 'appropriate/curl'
jq = 'local_tools/jq'

namespace = 'mulled'
github_repo = 'mulled/api'

-- Tasks

inv.task('main:generate_jq_image')
  .using('busybox')
    .run('mkdir', '-p', 'jq')
  .using('appropriate/curl')
    .run('--location', 'https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64', '-o', 'jq/jq-linux64')
  .using('busybox')
    .run('chmod', 'a+x', 'jq/jq-linux64')
  .wrap('jq').at('/')
    .withConfig({entrypoint = {'/bin/sh', '-c'}})
    .inImage('busybox').as(jq)
  .using('busybox')
    .run('rm', '-rf', 'jq')


parseDescriptions = '[.repositories[] |' -- use the repositories field
  .. '{key: .name, value: ' -- the values are generated next
  .. ' .description | split("---")[1] |' -- split the description into header and footer, separated by ---
  .. 'split("\n") |' -- split into lines
  .. 'map(select(startswith("* "))[2:])' -- take all lines starting with "* " and remove that prefix
  .. '}] | from_entries' -- output object

inv.task('main:load_versions_from_quay')
  .using(curl).run('https://quay.io/api/v1/repository?public=true&namespace=' .. namespace, '-o', 'data/quay_repository_search')
  .using(jq).run('/jq-linux64 \'' .. parseDescriptions .. '\' data/quay_repository_search > data/quay_versions')


parsePackages = 'split("\n") |' -- split input string into lines
  .. 'map(select(startswith("#") == false)) |' -- drop comments
  .. 'map(select((. | length) > 0)) |' -- drop empty lines (e.g. last line)
  .. 'map(split("\t")) |' -- split into tab delimited fields
  .. 'map({key: .[1], value: .[2]}) | from_entries' -- create object with names as keys, version as value

inv.task('main:load_versions_from_packages.tsv')
  .using(jq).run('/jq-linux64 --slurp --raw-input \'' .. parsePackages .. '\' packages.tsv > data/local_versions')


computeBuildList = '. as [$remotes, $locals] |' -- use variables for convenience
  .. '$locals | to_entries |' -- convert to entries array and map over them
  .. 'map(.key as $k | .value as $v | select('
  .. '  false == (' -- select(false == is comparable to reject
  .. '    ($remotes[$k]//[]) |' -- fetch the versions array (remotely) for that package, default to empty
  .. '    contains([$v]) ))) |' -- and answer whether this exact version is already present
  .. ' map(.key) | join("\n")' -- extract the package name (the key) and join by newlines
inv.task('main:generate_list:builds')
  .using(jq).run('/jq-linux64 --slurp --raw-output \'' .. computeBuildList .. '\' data/quay_versions data/local_versions > data/build_list')

computeDeleteList = '. as [$remotes, $locals] |' -- use variables for convenience
  .. '$remotes | keys |' -- extract remotely available package names
  .. 'map(. as $k | select( ($locals | has($k)) == false))' -- select all keys that are not present in the local package list
  .. '| join("\n")' -- join with newlines
inv.task('main:generate_list:deletes')
  .using(jq).run('/jq-linux64 --raw-output --slurp \'' .. computeDeleteList .. '\' data/quay_versions data/local_versions > data/delete_list')

inv.task('main:generate_lists')
  .runTask('main:generate_list:builds')
  .runTask('main:generate_list:deletes')

inv.task('main:create_data_dir')
  .using('busybox')
    .run('mkdir', '-p', 'data')

inv.task('main:fetch_images_dir_from_github')
  .using(curl)
    .run('https://api.github.com/repos/' .. github_repo .. '/contents/_images', '-o', 'data/github_repo')

inv.task('main:check_uniqueness_of_keys')
  .using('busybox')
    .run('/bin/sh', '-c',
      "cat packages.tsv | cut -f2 |" -- read in all package names
      .. "sort | uniq -d |" -- filter out non-duplicates
      .. "wc -l | xargs -I%% test 0 -eq %% || (echo 'Package names not unique' 1>&2 && false)") -- count number of non-duplicates and assert that there are zero of them

inv.task('main:prepare')
  .runTask('main:check_uniqueness_of_keys')
  .runTask('main:create_data_dir')
  .runTask('main:generate_jq_image')
  .runTask('main:load_versions_from_quay')
  .runTask('main:load_versions_from_packages.tsv')
  .runTask('main:generate_lists')
  .runTask('main:fetch_images_dir_from_github')

