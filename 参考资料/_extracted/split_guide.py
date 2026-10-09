import re
raw = open(r"参考资料\_extracted\全流程指南.txt", encoding="utf-8").read()
paras = re.split(r"[\r\n]+", raw)
out = []
for p in paras:
    p = p.strip()
    if not p:
        continue
    # 在句号后断行，避免超长行
    p = p.replace("。", "。\n")
    out.append(p)
open(r"参考资料\_extracted\全流程指南_分段.txt", "w", encoding="utf-8").write("\n".join(out))
print("段落数:", sum(len(x.splitlines()) for x in out))
