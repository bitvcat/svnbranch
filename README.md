# svnbranch
lua实现的svn 切版本的脚本。

## 使用
>可以把lua当作可执行文件来运行，只需要更改 svnbranch.lua 文件中的第一行代码，将你使用的lua解释器路径替换掉，然后赋予该脚本可执行权限。

使用方法如下：
```
chmod +x svnbranch.lua
./svnranche.lua
```

输出如下：

```
接下来的操作可能很危险,一切后果自负! 如果你不想继续请直接关闭窗口!

是否继续？[yes/no]
yes

请输入平台:
self

测试仓库：svn://192.168.1.254/proj-slg/trunk
测试仓库：ok
主干版本：52

请输入svn版本号(若不输入则表示取主干最新的版本号):


当前日期：20210521
备份分支：svn://192.168.1.254/proj-slg/branch/self_20210521_49
备份分支：成功
切换分支：self_20210521_52
切换分支：成功
写版本号：config/version.txt, version=20210521_52
写版本号：成功
```