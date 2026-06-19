# disk-usage-gui.ps1 - List largest files, select via GUI, send to Recycle Bin
# Recoverable: deleted files go to the Recycle Bin, not permanent delete

param(
    [string]$Path = "$env:USERPROFILE",
    [int]$TopFiles = 100,
    [int]$MinSizeMB = 50
)

if (-not (Test-Path $Path))
{ Write-Host "Path not found: $Path" -ForegroundColor Red; return 
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# For Recycle Bin support
Add-Type -AssemblyName Microsoft.VisualBasic

Write-Host "Scanning $Path ..." -ForegroundColor DarkGray
$minBytes = $MinSizeMB * 1MB
$files = Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -ge $minBytes } |
    Sort-Object Length -Descending |
    Select-Object -First $TopFiles

if (-not $files)
{ Write-Host "No files >= $MinSizeMB MB found under $Path." -ForegroundColor Yellow; return 
}

# --- Build the form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Disk Usage - select files to delete (Recycle Bin)"
$form.Size = New-Object System.Drawing.Size(900, 600)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Largest $($files.Count) files under: $Path  (check items to delete -> Recycle Bin)"
$label.Location = New-Object System.Drawing.Point(10, 10)
$label.Size = New-Object System.Drawing.Size(870, 20)
$form.Controls.Add($label)

# Grid with checkboxes
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(10, 35)
$grid.Size = New-Object System.Drawing.Size(865, 470)
$grid.Anchor = "Top,Bottom,Left,Right"
$grid.AllowUserToAddRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = "FullRowSelect"
$grid.AutoSizeColumnsMode = "Fill"

$colCheck = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colCheck.HeaderText = "Delete"
$colCheck.Name = "Delete"
$colCheck.FillWeight = 8
$grid.Columns.Add($colCheck) | Out-Null

$colSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSize.HeaderText = "Size (MB)"
$colSize.Name = "Size"
$colSize.ReadOnly = $true
$colSize.FillWeight = 12
$grid.Columns.Add($colSize) | Out-Null

$colPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPath.HeaderText = "Path"
$colPath.Name = "Path"
$colPath.ReadOnly = $true
$colPath.FillWeight = 80
$grid.Columns.Add($colPath) | Out-Null

foreach ($f in $files)
{
    $row = $grid.Rows.Add()
    $grid.Rows[$row].Cells["Delete"].Value = $false
    $grid.Rows[$row].Cells["Size"].Value = [math]::Round($f.Length / 1MB, 1)
    $grid.Rows[$row].Cells["Path"].Value = $f.FullName
}
$form.Controls.Add($grid)

# Buttons
$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "Delete selected (Recycle Bin)"
$btnDelete.Size = New-Object System.Drawing.Size(220, 30)
$btnDelete.Location = New-Object System.Drawing.Point(10, 515)
$btnDelete.Anchor = "Bottom,Left"
$form.Controls.Add($btnDelete)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Size = New-Object System.Drawing.Size(100, 30)
$btnCancel.Location = New-Object System.Drawing.Point(240, 515)
$btnCancel.Anchor = "Bottom,Left"
$btnCancel.Add_Click({ $form.Close() })
$form.Controls.Add($btnCancel)

$btnDelete.Add_Click({
        # Commit any in-progress checkbox edit
        $grid.EndEdit()
        $toDelete = @()
        foreach ($row in $grid.Rows)
        {
            if ($row.Cells["Delete"].Value -eq $true)
            {
                $toDelete += $row.Cells["Path"].Value
            }
        }
        if ($toDelete.Count -eq 0)
        {
            [System.Windows.Forms.MessageBox]::Show("Nothing selected.", "Info") | Out-Null
            return
        }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Send $($toDelete.Count) file(s) to the Recycle Bin?",
            "Confirm", "YesNo", "Question")
        if ($confirm -ne "Yes")
        { return 
        }

        $done = 0
        foreach ($p in $toDelete)
        {
            try
            {
                # Sends to Recycle Bin (recoverable) instead of permanent delete
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $p,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                $done++
            } catch
            {
                Write-Host "Failed: $p  ($($_.Exception.Message))" -ForegroundColor Red
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Sent $done file(s) to Recycle Bin.", "Done") | Out-Null
        # Remove deleted rows from the grid
        for ($i = $grid.Rows.Count - 1; $i -ge 0; $i--)
        {
            if ($grid.Rows[$i].Cells["Delete"].Value -eq $true)
            { $grid.Rows.RemoveAt($i) 
            }
        }
    })

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
