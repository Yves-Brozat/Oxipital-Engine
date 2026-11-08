param([string]$ProjectTitle='Oxipital Live Kinect Performance Synchronized.noisette',[switch]$ShowDashboard,[switch]$InspectOnly)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ChataigneForeground {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X,Y; }
    [StructLayout(LayoutKind.Sequential)] public struct Message { public IntPtr HWnd; public uint Msg; public UIntPtr WParam; public IntPtr LParam; public uint Time; public Point Pt; public uint Private; }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr window,int command);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from,uint to,bool attach);
    [DllImport("user32.dll")] public static extern bool PeekMessage(out Message message,IntPtr window,uint min,uint max,uint remove);
    [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr window,ref Point point);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr wParam,IntPtr lParam);
    public static bool Click(IntPtr window,int x,int y) {
        Point point=new Point { X=x,Y=y };
        if(!ScreenToClient(window,ref point)) return false;
        IntPtr position=new IntPtr((point.Y<<16)|(point.X&0xffff));
        return PostMessage(window,0x0201,new IntPtr(1),position) && PostMessage(window,0x0202,IntPtr.Zero,position);
    }
    public static uint ForegroundProcess() { uint process; GetWindowThreadProcessId(GetForegroundWindow(),out process); return process; }
    public static bool Focus(IntPtr target) {
        uint ignored; uint current=GetCurrentThreadId();
        uint foreground=GetWindowThreadProcessId(GetForegroundWindow(),out ignored);
        uint destination=GetWindowThreadProcessId(target,out ignored);
        Message message; PeekMessage(out message,IntPtr.Zero,0,0,0);
        bool attachedForeground=false,attachedTarget=false;
        try {
            if(foreground!=0 && foreground!=current) attachedForeground=AttachThreadInput(current,foreground,true);
            if(destination!=0 && destination!=current && destination!=foreground) attachedTarget=AttachThreadInput(current,destination,true);
            ShowWindowAsync(target,9);
            BringWindowToTop(target);
            SetForegroundWindow(target);
            return GetForegroundWindow()==target;
        } finally {
            if(attachedTarget) AttachThreadInput(current,destination,false);
            if(attachedForeground) AttachThreadInput(current,foreground,false);
        }
    }
}
'@
$candidates=@(Get-Process -Name Chataigne -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne 0})
$target=$candidates|Where-Object {$_.MainWindowTitle.Contains($ProjectTitle)}|Select-Object -First 1
if(!$target -and $candidates.Count -eq 1){$target=$candidates[0]}
if(!$target){throw 'No matching Chataigne window found.'}
$before=[ChataigneForeground]::ForegroundProcess()
if(!$InspectOnly){
    $focused=$false
    foreach($attempt in 1..3){
        if([ChataigneForeground]::Focus($target.MainWindowHandle)){$focused=$true;break}
        Start-Sleep -Milliseconds 100
    }
    if(!$focused){throw 'Windows refused Chataigne foreground activation.'}
}
$after=[ChataigneForeground]::ForegroundProcess()
$dashboardTabActivated=$false
if($ShowDashboard -and !$InspectOnly){
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $window=[System.Windows.Automation.AutomationElement]::FromHandle($target.MainWindowHandle)
    $elements=@{}
    foreach($name in @('Dashboard','State Machine','Module Router','Morpher')){
        $condition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$name)
        $elements[$name]=@($window.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition))
    }
    # JUCE exposes tabs as text controls. Identify the actual Dashboard tab by
    # its neighbouring panel tabs, excluding the state also named Dashboard.
    $tab=$null
    foreach($candidate in $elements['Dashboard']){
        $rect=$candidate.Current.BoundingRectangle
        if($rect.IsEmpty -or $rect.Width -le 0 -or $candidate.Current.IsOffscreen){continue}
        foreach($name in @('State Machine','Module Router','Morpher')){
            foreach($peer in $elements[$name]){
                $other=$peer.Current.BoundingRectangle
                if(!$other.IsEmpty -and [Math]::Abs($rect.Top-$other.Top) -lt 3 -and [Math]::Abs($rect.Height-$other.Height) -lt 3){$tab=$candidate;break}
            }
            if($tab){break}
        }
        if($tab){break}
    }
    if(!$tab){throw 'Dashboard panel tab not found in the accessible Chataigne window.'}
    $rect=$tab.Current.BoundingRectangle
    $dashboardTabActivated=[ChataigneForeground]::Click($target.MainWindowHandle,[int]($rect.Left+$rect.Width/2),[int]($rect.Top+$rect.Height/2))
    if(!$dashboardTabActivated){throw 'Dashboard tab activation could not be posted.'}
}
[pscustomobject]@{TargetProcess=$target.Id;ForegroundBefore=$before;ForegroundAfter=$after;Focused=($after -eq $target.Id);DashboardTabActivated=$dashboardTabActivated;InspectOnly=[bool]$InspectOnly}|ConvertTo-Json -Compress
