#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const child_process = require('child_process')

function filterFile(file) {
  return !( file.endsWith(".nuspec")
         || file.endsWith(".txt")
          )
}

function usage () {
  console.error("usage: ./deps-to-nix project/obj/project.assets.json")
  process.exit(1)
}

function loadLibraries(file) {
  let json = JSON.parse(fs.readFileSync(file));

  return Object.keys(json.libraries).reduce((obj, key) => {
    let lib = json.libraries[key]

    if (lib.type === 'project') {
      let otherProj = path.dirname(lib.path)
      try {
        let otherAssets = path.join(otherProj, "obj/project.assets.json")
        let otherJson = loadLibraries(otherAssets)
        Object.assign(otherJson, obj)
      }
      catch (e) {
        //console.error(e)
      }
      return obj
    }
    else {
      obj[key] = lib
    }

    return obj
  }, {})
}

if (process.argv.length < 3)
  usage()

let libraries = loadLibraries(process.argv[2]);
let pkgs = []

for (let key in libraries) {
  let lib = libraries[key]

  let [name, ver] = key.split('/')
  let sha256 = child_process.execSync(`nix-prefetch-url https://www.nuget.org/api/v2/package/${name}/${ver}`).toString().trim();
  let sha512 = new Buffer(lib.sha512, 'base64').toString('hex')

  pkgs.push({
    baseName: name,
    version: ver,
    sha512: sha512,
    sha256: sha256,
    path: lib.path,
    outputFiles: lib.files.filter(filterFile)
  })

}

console.log(JSON.stringify(pkgs, null, 4))
