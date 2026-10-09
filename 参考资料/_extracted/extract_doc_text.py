# 从旧版 .doc（OLE 复合文档）中粗提取 UTF-16LE 中文正文
# 用途：LibreOffice 拒绝解析该文件时的降级方案（只求可读，不求完美格式）
import re
import sys

SRC = sys.argv[1]
DST = sys.argv[2]

data = open(SRC, "rb").read()
text = data.decode("utf-16-le", errors="ignore")

# 保留中日韩文、常用全半角标点、字母数字和空白的长段落
runs = re.findall(r"[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef\u2014\u2018\u2019\u201c\u201d\u2026a-zA-Z0-9，。；：、！？（）·×\-\+%/\.\s]{12,}", text)

out = []
seen_prev = ""
for r in runs:
    r = re.sub(r"[ \t\u3000]{2,}", " ", r).strip()
    if len(r) < 12:
        continue
    if r == seen_prev:  # OLE 扇区边界重复
        continue
    out.append(r)
    seen_prev = r

with open(DST, "w", encoding="utf-8") as f:
    f.write("\n".join(out))

print(f"提取段落数: {len(out)}, 总字符: {sum(len(x) for x in out)}")
