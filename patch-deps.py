#!/usr/bin/env python3
### ponytail: guacamole 1.6.0 has no newer release with updated deps; swap vulnerable
### nested/regular jars for fixed versions from Maven Central at build time.
import os
import urllib.request
import zipfile

BASE = "https://repo1.maven.org/maven2/"
GUAC = "/opt/guacamole"

# new-entry-name -> maven path
FETCH = {
    "jackson-core-2.21.6.jar": "com/fasterxml/jackson/core/jackson-core/2.21.6/jackson-core-2.21.6.jar",
    "jackson-databind-2.21.6.jar": "com/fasterxml/jackson/core/jackson-databind/2.21.6/jackson-databind-2.21.6.jar",
    "jackson-annotations-2.21.jar": "com/fasterxml/jackson/core/jackson-annotations/2.21/jackson-annotations-2.21.jar",
    "jackson-dataformat-yaml-2.21.6.jar": "com/fasterxml/jackson/dataformat/jackson-dataformat-yaml/2.21.6/jackson-dataformat-yaml-2.21.6.jar",
    "jackson-module-jaxb-annotations-2.21.6.jar": "com/fasterxml/jackson/module/jackson-module-jaxb-annotations/2.21.6/jackson-module-jaxb-annotations-2.21.6.jar",
    "mina-core-2.2.8.jar": "org/apache/mina/mina-core/2.2.8/mina-core-2.2.8.jar",
    "commons-lang3-3.18.0.jar": "org/apache/commons/commons-lang3/3.18.0/commons-lang3-3.18.0.jar",
    "bcprov-jdk15to18-1.84.jar": "org/bouncycastle/bcprov-jdk15to18/1.84/bcprov-jdk15to18-1.84.jar",
    "bcpkix-jdk15to18-1.84.jar": "org/bouncycastle/bcpkix-jdk15to18/1.84/bcpkix-jdk15to18-1.84.jar",
    "bcutil-jdk15to18-1.84.jar": "org/bouncycastle/bcutil-jdk15to18/1.84/bcutil-jdk15to18-1.84.jar",
    "bc-fips-2.1.2.jar": "org/bouncycastle/bc-fips/2.1.2/bc-fips-2.1.2.jar",
    "logback-core-1.3.16.jar": "ch/qos/logback/logback-core/1.3.16/logback-core-1.3.16.jar",
    "logback-classic-1.3.16.jar": "ch/qos/logback/logback-classic/1.3.16/logback-classic-1.3.16.jar",
    "mssql-jdbc-10.2.4.jre11.jar": "com/microsoft/sqlserver/mssql-jdbc/10.2.4.jre11/mssql-jdbc-10.2.4.jre11.jar",
}

# old-entry-name -> new-entry-name (matched by basename inside .jar/.war archives)
REPLACE = {
    "jackson-core-2.19.0.jar": "jackson-core-2.21.6.jar",
    "jackson-databind-2.19.0.jar": "jackson-databind-2.21.6.jar",
    "jackson-annotations-2.19.0.jar": "jackson-annotations-2.21.jar",
    "jackson-dataformat-yaml-2.19.0.jar": "jackson-dataformat-yaml-2.21.6.jar",
    "jackson-module-jaxb-annotations-2.19.0.jar": "jackson-module-jaxb-annotations-2.21.6.jar",
    "mina-core-2.2.4.jar": "mina-core-2.2.8.jar",
    "commons-lang3-3.17.0.jar": "commons-lang3-3.18.0.jar",
    "bcprov-jdk15to18-1.80.jar": "bcprov-jdk15to18-1.84.jar",
    "bcpkix-jdk15to18-1.80.jar": "bcpkix-jdk15to18-1.84.jar",
    "bcutil-jdk15to18-1.80.jar": "bcutil-jdk15to18-1.84.jar",
    "bc-fips-2.1.0.jar": "bc-fips-2.1.2.jar",
    "logback-core-1.3.15.jar": "logback-core-1.3.16.jar",
    "logback-classic-1.3.15.jar": "logback-classic-1.3.16.jar",
}

_cache = {}


def fetch(name):
    if name not in _cache:
        _cache[name] = urllib.request.urlopen(BASE + FETCH[name]).read()
    return _cache[name]


def manifest_version(jar_bytes):
    z = zipfile.ZipFile(__import__("io").BytesIO(jar_bytes))
    if "META-INF/MANIFEST.MF" not in z.namelist():
        return "n/a"
    for line in z.read("META-INF/MANIFEST.MF").decode(errors="replace").splitlines():
        if line.startswith("Implementation-Version:"):
            return line.split(":", 1)[1].strip()
    return "n/a"


def plain_file(path):
    if not os.path.exists(path):
        return False
    data = fetch("mssql-jdbc-10.2.4.jre11.jar")
    with open(path, "wb") as f:
        f.write(data)
    print(f"  {os.path.basename(path)}: mssql-jdbc 9.4.1 -> 10.2.4 (manifest {manifest_version(data)})")
    return True


def fix_bytes(data, label, depth=0):
    import io
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        return data, 0
    infos = z.namelist()
    changed = {}  # old-entry -> (new-entry, bytes)
    for n in infos:
        base = n.rsplit("/", 1)[-1]
        if base in REPLACE:
            new_name = n.rsplit("/", 1)[0] + "/" + REPLACE[base] if "/" in n else REPLACE[base]
            changed[n] = (new_name, fetch(REPLACE[base]))
    nested = {}  # entry -> patched inner-jar bytes
    for n in infos:
        if n.endswith(".jar") and n not in changed:
            inner, c = fix_bytes(z.read(n), f"{label}!{n}", depth + 1)
            if c:
                nested[n] = inner
    if not changed and not nested:
        return data, 0
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as zout:
        for n in infos:
            old = z.getinfo(n)
            new_name, d = changed[n] if n in changed else (n, nested.get(n, z.read(n)))
            zi = zipfile.ZipInfo(new_name, date_time=old.date_time)
            zi.compress_type = old.compress_type
            zi.external_attr = old.external_attr
            zout.writestr(zi, d)
    for n, (new_name, d) in changed.items():
        print("  " * depth + f"{label}!{n}: -> {new_name} (manifest {manifest_version(d)})")
    for n in nested:
        print("  " * depth + f"{label}!{n}: nested jar patched in place")
    return out.getvalue(), len(changed) + len(nested)


def rewrite(path):
    with open(path, "rb") as f:
        data = f.read()
    new, n = fix_bytes(data, path)
    if n:
        with open(path, "wb") as f:
            f.write(new)
    return n


total = 0
for target in ("drivers/mssql-jdbc.jar", "environment/SQLSERVER_/lib/mssql-jdbc.jar"):
    total += plain_file(os.path.join(GUAC, target))

for root, _dirs, files in os.walk(GUAC):
    for fn in sorted(files):
        if fn.endswith((".jar", ".war")):
            n = rewrite(os.path.join(root, fn))
            if n:
                print(f"{os.path.join(root, fn)}: {n} entr{'y' if n == 1 else 'ies'} replaced")
                total += n

assert total > 0, "no jars replaced - image layout changed?"
print(f"OK: {total} jar replacements")
