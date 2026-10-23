# Tripwire hashing for testenv.sh (run with python3 -I). Content hashes, never size/mtime: a same-size rewrite must show up.
#   markers BOTTLES      one line per cache-marker file (bottles/*/options/**, except *.env): "<hash>  <bottle>/options/<path>"
#   regkeys BOTTLES      one line per key of every bottle's system/user/userdef.reg: "<bottle>/<file>\t[key]\t<hash>\t<owned>"
# owned = 1 for keys Cosmopolitan owns: every AppDefaults key and DllOverrides in user.reg, and the keys in that bottle's registry ledger
# (options/.registry-ledger.json; HKCU\… keys live in user.reg, HKLM\… in system.reg). Keys compare case-insensitively, like Wine's.
import hashlib, json, os, sys

def h(data): return hashlib.sha256(data).hexdigest()[:16]

def markers(root):
    for b in sorted(os.listdir(root)):
        for d, _, files in sorted(os.walk(os.path.join(root, b, "options"))):
            for n in sorted(files):
                if n.endswith(".env"): continue
                p = os.path.join(d, n)
                try: print(h(open(p, "rb").read()), os.path.relpath(p, root), sep="  ")
                except OSError: print("unreadable", os.path.relpath(p, root), sep="  ")

def regkeys(root):
    for b in sorted(os.listdir(root)):
        try: ledger = json.load(open(os.path.join(root, b, "options", ".registry-ledger.json")))
        except (OSError, ValueError): ledger = []
        mine = {("user.reg" if e["key"].upper().startswith("HKCU\\") else "system.reg", "[" + e["key"].split("\\", 1)[1].replace("\\", "\\\\").lower() + "]")
                for e in ledger if isinstance(e, dict) and "\\" in str(e.get("key", ""))}
        for name in ("system.reg", "user.reg", "userdef.reg"):
            p = os.path.join(root, b, name)
            if not os.path.isfile(p): continue
            def owned(k):
                k = k.lower()
                return (name, k) in mine or name == "user.reg" and (k.startswith("[software\\\\wine\\\\appdefaults\\\\") or k == "[software\\\\wine\\\\dlloverrides]")
            key, buf = "(file header)", []
            def emit(): print(f"{b}/{name}", key, h(b"".join(buf)), int(owned(key)), sep="\t")
            for line in open(p, "rb"):
                if line.startswith(b"["):
                    emit(); key, buf = line[:line.rindex(b"]") + 1].decode("utf-8", "replace"), []
                buf.append(line)
            emit()

if __name__ == "__main__":
    {"markers": markers, "regkeys": regkeys}[sys.argv[1]](sys.argv[2])
