import importlib.util, shutil, os, sys
W=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec=importlib.util.spec_from_file_location("bp",W+"/build_patches.py"); bp=importlib.util.module_from_spec(spec); spec.loader.exec_module(bp)
orig=bp.asm; repl=dict(a.split("=") for a in sys.argv[2:])
def asm2(name,org,syms):
    if name in repl:
        shutil.copy(repl[name], W+"/asm/_dbg.s"); r=orig("_dbg",org,syms); os.remove(W+"/asm/_dbg.s"); return r
    return orig(name,org,syms)
bp.asm=asm2; open(sys.argv[1],"wb").write(bp.build_ddraw()); print("built",sys.argv[1])
