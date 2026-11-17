import io
import sys

path = sys.argv[1]
old_marketing, new_marketing, old_build, new_build = sys.argv[2:6]
text = io.open(path, encoding="utf-8").read()
text = text.replace('MARKETING_VERSION: "%s"' % old_marketing, 'MARKETING_VERSION: "%s"' % new_marketing)
text = text.replace('CURRENT_PROJECT_VERSION: "%s"' % old_build, 'CURRENT_PROJECT_VERSION: "%s"' % new_build)
text = text.replace('CFBundleShortVersionString: "%s"' % old_marketing, 'CFBundleShortVersionString: "%s"' % new_marketing)
text = text.replace('CFBundleVersion: "%s"' % old_build, 'CFBundleVersion: "%s"' % new_build)
io.open(path, "w", encoding="utf-8", newline="\n").write(text)
print("bumped to %s (%s)" % (new_marketing, new_build))
