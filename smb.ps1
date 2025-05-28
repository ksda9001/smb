# 添加 Windows Forms 与绘图组件引用
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 定义全局日志文本框变量
$global:txtLog = $null

# 辅助函数：向日志文本框及控制台输出日志信息
function Write-Log {
    param ([string]$Message)
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $str = "$timestamp - $Message"
    if ($global:txtLog) {
        $global:txtLog.AppendText($str + "`r`n")
    }
    Write-Output $str
}

# 注册计划任务函数，任务在系统启动时自动执行 netsh 命令
function Register-NetshTask {
    try {
        if (Get-ScheduledTask -TaskName "NetshPortProxyTask" -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName "NetshPortProxyTask" -Confirm:$false
            Write-Log "旧的计划任务 'NetshPortProxyTask' 已被删除。"
        }
        # 构造 netsh 命令字符串（注意双引号转义）
        $netshCmd = 'netsh interface portproxy add v4tov4 listenport=445 listenaddress=127.0.0.1 connectport=4445 connectaddress=39.103.49.166'
        $actionObj = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"$netshCmd`""
        $triggerObj = New-ScheduledTaskTrigger -AtStartup
        $settingsObj = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName "NetshPortProxyTask" -Action $actionObj -Trigger $triggerObj -Settings $settingsObj -RunLevel Highest -Force
        Write-Log "计划任务 'NetshPortProxyTask' 已注册，在系统启动时自动执行 netsh 命令。"
    }
    catch {
        Write-Log "注册计划任务失败: $($_.Exception.Message)"
    }
}

# 功能1：配置 netsh 命令与计划任务，同时处理服务的关闭操作
function Setup-Function {
    try {
        $serverService = Get-Service -Name "LanmanServer" -ErrorAction SilentlyContinue
        if (-not $serverService) {
            Write-Log "未找到名为 'LanmanServer' 的服务，请检查服务名称。"
            return
        }
        if ($serverService.Status -eq "Running") {
            Write-Log "'LanmanServer' 服务正在运行，正在尝试停止..."
            Stop-Service -Name "LanmanServer" -Force -ErrorAction Stop
            Write-Log "'LanmanServer' 服务已停止。"

            Write-Log "将 'LanmanServer' 服务启动类型设置为禁用..."
            sc.exe config "LanmanServer" start= disabled | Out-Null
            Write-Log "'LanmanServer' 服务启动类型已设置为禁用。"

            Write-Log "注册计划任务，重启后执行 netsh 命令..."
            Register-NetshTask
            Write-Log "请重启系统以完成 netsh 命令的自动执行。"
        }
        else {
            Write-Log "'LanmanServer' 服务已处于停止状态。立即执行 netsh 命令..."
            netsh interface portproxy add v4tov4 listenport=445 listenaddress=127.0.0.1 connectport=4445 connectaddress=39.103.49.166
            Write-Log "netsh 命令执行成功。"
            Write-Log "注册计划任务，确保系统启动时自动执行该命令..."
            Register-NetshTask
        }
    }
    catch {
        Write-Log "执行配置过程中出错：$($_.Exception.Message)"
    }
}

# 功能2：启动服务前删除自启动任务，并设置服务启动类型为自动，然后启动服务
function Start-ServerService {
    try {
        Write-Log "正在检查是否存在自启动任务 'NetshPortProxyTask'..."
        $existingTask = Get-ScheduledTask -TaskName "NetshPortProxyTask" -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName "NetshPortProxyTask" -Confirm:$false
            Write-Log "检测到自启动任务 'NetshPortProxyTask'，已删除。"
        }
        else {
            Write-Log "未检测到自启动任务。"
        }

        Write-Log "将 'LanmanServer' 服务启动类型设置为自动..."
        sc.exe config "LanmanServer" start= auto | Out-Null
        Write-Log "'LanmanServer' 服务启动类型已设置为自动。"

        Write-Log "正在启动 'LanmanServer' 服务..."
        Start-Service -Name "LanmanServer" -ErrorAction Stop
        Write-Log "'LanmanServer' 服务启动成功。"
    }
    catch {
        Write-Log "启动 'LanmanServer' 服务失败：$($_.Exception.Message)"
    }
}

# 构建图形用户界面
$form = New-Object System.Windows.Forms.Form
$form.Text = "SMB端口转发配置工具"
$form.Size = New-Object System.Drawing.Size(600, 400)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# 创建“配置 netsh 及任务注册”按钮
$btnSetup = New-Object System.Windows.Forms.Button
$btnSetup.Location = New-Object System.Drawing.Point(20, 20)
$btnSetup.Size = New-Object System.Drawing.Size(250, 60)
$btnSetup.Text = "启动SMB端口转发并设置自启动"

# 创建“启动 Server 服务”按钮
$btnStartServer = New-Object System.Windows.Forms.Button
$btnStartServer.Location = New-Object System.Drawing.Point(290, 20)
$btnStartServer.Size = New-Object System.Drawing.Size(250, 60)
$btnStartServer.Text = "取消SMB端口转发(还原一切改动)"

# 创建多行日志输出文本框
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 80)
$txtLog.Size = New-Object System.Drawing.Size(520, 260)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas",10)
$global:txtLog = $txtLog

# 为按钮添加点击事件处理
$btnSetup.Add_Click({
    $global:txtLog.Text = ""
    Write-Log "【操作开始】执行配置功能..."
    Setup-Function
    Write-Log "【操作结束】"
})

$btnStartServer.Add_Click({
    $global:txtLog.Text = ""
    Write-Log "【操作开始】启动 Server 服务并检查自启动任务..."
    Start-ServerService
    Write-Log "【操作结束】"
})

# 将控件添加到窗体中
$form.Controls.Add($btnSetup)
$form.Controls.Add($btnStartServer)
$form.Controls.Add($txtLog)

# 显示窗体
[System.Windows.Forms.Application]::Run($form)
