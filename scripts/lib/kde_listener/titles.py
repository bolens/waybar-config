import re


def trim_title(s, max_len=70):
    s = s.replace('\n', ' ').replace('\t', ' ')
    s = re.sub(r'\s+', ' ', s).strip()

    s = re.sub(r'(.*) - Mozilla Firefox$', r'\1', s)
    s = re.sub(r'(.*) - Zen Browser$', r'\1', s)
    s = re.sub(r'(.*) - Google Chrome$', r'\1', s)
    s = re.sub(r'(.*) - Floorp$', r'\1', s)
    s = re.sub(r'(.*) - Chromium$', r'\1', s)
    s = re.sub(r'(.*) - Brave$', r'\1', s)
    s = re.sub(r'(.*) - Vivaldi$', r'\1', s)

    if len(s) <= max_len:
        return s
    else:
        return s[:max_len - 3] + "..."


def clean_title(s):
    s = s.replace('\n', ' ').replace('\t', ' ')
    s = re.sub(r'\s+', ' ', s).strip()

    s = re.sub(r'(.*) - Mozilla Firefox$', r'\1', s)
    s = re.sub(r'(.*) - Zen Browser$', r'\1', s)
    s = re.sub(r'(.*) - Google Chrome$', r'\1', s)
    s = re.sub(r'(.*) - Floorp$', r'\1', s)
    s = re.sub(r'(.*) - Chromium$', r'\1', s)
    s = re.sub(r'(.*) - Brave$', r'\1', s)
    s = re.sub(r'(.*) - Vivaldi$', r'\1', s)
    return s
