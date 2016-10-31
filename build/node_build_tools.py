import zipfile

with zipfile.ZipFile('src/build/node_build_tools.zip', "r") as z:
    z.extractall('src/third_party/node/build')
