# -*- coding: utf-8 -*-
"""配置脱敏：把 token / QQ 号 / 密钥替换成占位符，用于对外打包。

用法：python sanitize_config.py <源文件> <输出文件>
规则只针对明确的敏感字段，避免误伤普通数字（比如超时毫秒数）。
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()

# 1) 键值型：token / apiKey / accessToken / secret
kv_rules = [
    (r"(onebotToken\s*:\s*)\S+", r"\1YOUR_ONEBOT_TOKEN"),
    (r"(httpToken\s*:\s*)\S+", r"\1YOUR_HTTP_TOKEN"),
    (r"(accessToken\s*:\s*)\S+", r"\1YOUR_ACCESS_TOKEN"),
    (r"(apiKey\s*:\s*)\S+", r"\1YOUR_API_KEY"),
    (r"(secret\s*:\s*)\S+", r"\1YOUR_SECRET"),
]
for pat, rep in kv_rules:
    t = re.sub(pat, rep, t, flags=re.M)

# 2) selfId: '123456'
t = re.sub(r"(selfId\s*:\s*)'?\d{5,}'?", r"\1'YOUR_QQ_ID'", t, flags=re.M)

# 3) 只处理 YAML 列表项里的长数字（owners / privateAllow / groupAllow）
t = re.sub(r"^(\s*-\s*)'?(\d{5,})'?\s*$", r"\1'YOUR_QQ_ID'", t, flags=re.M)

# 4) 群号、QQ 号出现在其他键下（如 groupAllow: ['123456']）
# 注意：替换后必须带单引号，否则 YAML 里会变成裸标量（解析器可能报错）
def _fix_list(m):
    inner = re.sub(r"'?(\d{5,})'?", "'YOUR_QQ_ID'", m.group(2))
    return m.group(1) + inner + m.group(3)


t = re.sub(r"(\b(?:owners|privateAllow|groupAllow|deny\w*)\s*:\s*\[)([^\]]*)(\])", _fix_list, t)

open(dst, "w", encoding="utf-8").write(t)
print("sanitized:", dst, len(t), "chars")
