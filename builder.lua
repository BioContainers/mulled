
-- Settings
curl = 'appropriate/curl'
jq = 'local_tools/jq'

quay_prefix = 'mulled'
namespace = 'quay.io/' .. quay_prefix
github_repo = 'mulled/api'

builders = {}

current_build_id = 'snapshot'

------------------------------------------------------------------------
------------- ALPINE
------------------------------------------------------------------------
builders.alpine = function (package, revision, test, builddir)
  repo = namespace .. '/' .. package .. ':' .. revision

extractInfo = 'apk info --root /data/dist -wd  ' .. package .. [==[
| (
  read fline ;
  echo $fline | cut -d" " -f1 | cut -d"-" -f 2-3 > /data/info/version;
  read desc; echo  $desc > /data/info/description ;
  read discard ;
  read discard ;
  read homepage ; echo $homepage > /data/info/homepage ;
)
]==]

  install = [==[ apk --root /data/dist --update-cache --repository http://dl-4.alpinelinux.org/alpine/v3.2/main --keys-dir /etc/apk/keys --initdb add ]==]

  inv.task('build:' .. package)
    .using('alpine')
      .withConfig({entrypoint = {"/bin/sh", "-c"}})
      .withHostConfig({
        binds = {builddir .. ':/data'}
      })
      .run('mkdir -p /data/dist /data/info')
      .run(install .. package .. ' && ' .. extractInfo)
      .run('rm -rf /data/dist/lib/apk /data/dist/var/cache/apk/')

      .wrap(builddir .. '/dist').at('/').inImage('busybox:latest')
        .as(repo)

  inv.task('clean:' .. package)
    .using('alpine')
      .withHostConfig({binds = {builddir .. ':/data'}})
      .run('rm', '-rf', '/data/dist', '/data/info')

  inv.task('test:' .. package)
    .using(repo)
    .withConfig({entrypoint = {'/bin/sh', '-c'}})
    .run(test)
end

------------------------------------------------------------------------
------------- LINUXBREW
------------------------------------------------------------------------
builders.linuxbrew = function (package, revision, test, builddir)
  repo = namespace .. '/' .. package .. ':' .. revision

  extractInfo = '$BREW info --json=v1 ' .. package ..
[==[ | jq --raw-output '.[0] | [.homepage, .desc, .versions.stable] | join("\n")' | (
  read homepage ; echo $homepage > /info/homepage ;
  read desc ; echo $desc > /info/description ;
  read version ; echo $version > /info/version ;
) ]==]

  inv.task('build:' .. package)
    .using('thriqon/linuxbrew-alpine')
      .withConfig({user = "root"})
      .withHostConfig({
        binds = {builddir .. ':/data'}
      })
      .run('mkdir', '-p', '/data/info', '/data/dist')
      .run('chown', 'nobody', '/data/info', '/data/dist/')

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
    .wrap(builddir .. '/dist').inImage('mwcampbell/muslbase-runtime')
      .at("/brew/").as(repo)

  inv.task('clean:' .. package)
  .using('thriqon/linuxbrew-alpine')
    .withConfig({user = "root"})
    .withHostConfig({
      binds = {builddir .. ':/data'}
    })
    .run('rm', '-rf', '/data/dist', '/data/info')

  inv.task('test:' .. package)
    .using(repo)
    .withConfig({entrypoint = {'/bin/sh', '-c'}})
    .run(test)
end

------------------------------------------------------------------------
------------- CONDA
------------------------------------------------------------------------
builders.conda = function (package, revision, test, builddir)
  repo = namespace .. '/' .. package .. ':' .. revision
  channels = {"bioconda", "r"}

  channelArgs = ""
  for i, c in pairs(channels) do
    channelArgs = channelArgs .. "--channel " .. c .. " "
  end

  install = [==[ conda install ]==] .. channelArgs .. [==[ -p /data/dist --copy --yes ]==]
  extractInfo = 'conda list -p /data/dist -e ' .. package .. ' | grep ^' .. package .. '= | tr = - | xargs -I %% cp /opt/conda/pkgs/%%/info/recipe.json /data/info/raw.json'

  transformInfo = '/jq-linux64 --raw-output  \'[.about.home, .about.summary, .package.version] | join("\n")\' /data/info/raw.json | '
    .. [==[ ( read homepage ; echo $homepage > /data/info/homepage ; read desc ; echo $desc > /data/info/description ; read version ; echo $version > /data/info/version ) ]==]

  linkLib64 = 'ln -s /lib /data/dist/lib64'

  inv.task('build:' .. package)
  .using('continuumio/miniconda')
    .withConfig({entrypoint = {"/bin/sh", "-c"}})
    .withHostConfig({
      binds = {builddir .. ':/data'}
    })
    .run('mkdir -p /data/dist /data/info')
    .run(install .. package .. ' && ' .. extractInfo)
    .run(linkLib64)

  .using(jq)
    .withHostConfig({binds = {builddir .. ':/data'}})
    .run(transformInfo)
  .wrap(builddir .. '/dist').at('/').inImage('busybox:ubuntu')
    .as(repo)

  inv.task('clean:' .. package)
    .using('continuumio/miniconda')
      .withConfig({entrypoint = {"/bin/sh", "-c"}})
      .withHostConfig({
        binds = {builddir .. ':/data'}
      })
      .run('rm -rf /data/dist /data/info')

  inv.task('test:' .. package)
    .using(repo)
    .withConfig({entrypoint = {'/bin/sh', '-c'}})
    .run(test)
end

function pushTask(package, new_revision, packager, builddir)
  inv.task('push:' .. package)
  -- tag as latest
    .tag(namespace .. '/' .. package .. ':' .. new_revision)
      .as(namespace .. '/' .. package)
  -- create repo if needed
    .using(curl)
      .withConfig({env = {"TOKEN=" .. ENV.TOKEN}})
      .run('/bin/sh',  '-c', 'curl --fail -X POST -HAuthorization:Bearer\\ $TOKEN -HContent-Type:application/json '
          .. '-d \'{"namespace": "' .. quay_prefix .. '", "visibility": "public", '
          .. '"repository": "' .. package .. '", "description": ""}\' '
          .. 'https://quay.io/api/v1/repository || true')
  -- upload image
    .using('docker')
      .withHostConfig({
        binds = {
          "/var/run/docker.sock:/var/run/docker.sock",
          ENV.HOME .. "/.docker:/root/.docker",
          builddir .. ':/pkg'
        }
      })
      .run('/bin/sh', '-c', 
        'docker push ' .. namespace .. '/' .. package .. ':' .. new_revision .. ' | grep digest | grep "' .. new_revision .. ': " | cut -d" " -f 3 > /pkg/info/checksum')
      .run('docker', 'push', namespace .. '/' .. package)
      .run('/bin/sh', '-c',
        'docker inspect -f "{{.VirtualSize}}" ' .. namespace .. '/' .. package .. ':' .. new_revision .. ' > /pkg/info/size')
  -- generate new description
    .using(jq)
      .withHostConfig({binds = {
        builddir .. ':/pkg',
        './data:/data'
      }})
      .run('('
        .. 'echo "# ' .. package .. '" ; echo; '
        .. 'echo -n "> "; cat /pkg/info/description; echo; '
        .. 'cat /pkg/info/homepage; echo; '
        .. 'echo "Latest revision: ' .. new_revision .. '"; echo; '
        .. 'echo "---" ; echo; '
        .. 'echo "## Available revisions"; echo; '
        .. '/jq-linux64 --raw-output \'(.' .. package .. '//[]) | map("* " + .) | join("\n")\' /data/quay_versions; '
        .. 'echo "* ' .. new_revision .. '" ; echo; '
        .. 'echo ) | /jq-linux64 --raw-input --slurp \'{description: .}\' > /pkg/info/quay_description')

  -- put new description
    .using(curl)
      .withHostConfig({binds = {builddir .. ':/pkg'}})
      .withConfig({env = {"TOKEN=" .. ENV.TOKEN}})
      .run('/bin/sh', '-c', 'curl --fail -HAuthorization:Bearer\\ $TOKEN -T /pkg/info/quay_description  '
          .. '-HContent-type:application/json '
          .. 'https://quay.io/api/v1/repository/' .. quay_prefix .. '/' .. package)
  -- fetch current SHA
    .using(jq)
      .withHostConfig({binds = {builddir .. ':/pkg', './data:/data'}})
      .run('/jq-linux64 --raw-output \'map(select(.name == "' .. package .. '.json"))[0].sha\' /data/github_repo > /pkg/info/previous_file_sha')
  -- generate image json
    .using(jq)
      .withHostConfig({binds = {builddir .. ':/pkg'}})
      .run('/jq-linux64 --raw-input --slurp \'.|split("\n") as $i | {'
        .. 'message: "build ' .. ENV.TRAVIS_BUILD_NUMBER .. '\n\nbuild url: ' .. current_build_id .. '", '
        .. 'content: ("---\n---\n" + ({'
          .. 'image: "' .. package .. '",'
          .. 'date: (now | todate),'
          .. 'buildurl: "' .. current_build_id .. '",'
          .. 'packager: "' .. packager .. '", '
          .. 'homepage: $i[0], description: $i[1], version: $i[2], checksum: $i[3], size: $i[4]'
        .. '} | tostring) | @base64), '
        -- todo add checksum size
        .. 'sha: $i[5]}\' /pkg/info/homepage /pkg/info/description /pkg/info/version /pkg/info/checksum /pkg/info/size /pkg/info/previous_file_sha  > /pkg/info/github_commit')
  -- put image json to github
    .using(curl)
      .withHostConfig({binds = {builddir .. ':/pkg'}})
      .withConfig({env = {"TOKEN=" .. ENV.GITHUB_TOKEN}})
      .run('/bin/sh',  '-c', 'curl --fail -HAuthorization:Bearer\\ $TOKEN -HContent-Type:application/json '
        .. '-T /pkg/info/github_commit https://api.github.com/repos/' .. github_repo .. '/contents/_images/' .. package .. '.json')
end

-- split line by tabs
function split(s)
  local start = 1
  local t = {}
  while true do
    local pos = string.find(s, "\t", start, true)
    if not pos then
      break
    end
    table.insert(t, string.sub(s, start, pos - 1))
    start = pos + 1
  end
  table.insert(t, string.sub(s, start))
  return t
end

-- registered packages
registered_packages = {}
for line in io.lines("packages.tsv") do
  fields = split(line)
  registered_packages[fields[2]] = fields
end

pr = inv.task('pr')
prod = inv.task('prod')

local build_counter = 0

-- build tasks
for line in io.lines("data/build_list") do
  local fields = registered_packages[line]

  local packager = fields[1]
  local package = fields[2]
  local revision = fields[3]
  local test = fields[4]

  assert(builders[packager])
  build_counter = build_counter + 1
  builddir = './mulled-build-' .. tostring(build_counter)
  builders[packager](package, revision, test, builddir)

  pushTask(package, revision, packager, builddir)

  pr.runTask('build:' .. package).runTask('test:' .. package).runTask('clean:' .. package)
  prod.runTask('build:' .. package).runTask('test:' .. package).runTask('push:' .. package).runTask('clean:' .. package)
end

