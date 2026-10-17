# _view-logo.ps1 - ASCII visualization of alpha channel
# Usage: -SrcPath <png> [-Thresh 32] [-Cols 60] [-Rows 30]
param(
  [Parameter(Mandatory=$true)][string]$SrcPath,
  [int]$Thresh = 32,
  [int]$Cols = 60,
  [int]$Rows = 30
)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class LogoView2 {
  public static string View(string path, int cols, int rows, int thresh) {
    using (Bitmap bmp = new Bitmap(path)) {
      int w = bmp.Width, h = bmp.Height;
      BitmapData d = bmp.LockBits(new Rectangle(0,0,w,h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      int stride = d.Stride; byte[] buf = new byte[Math.Abs(stride)*h];
      Marshal.Copy(d.Scan0, buf, 0, buf.Length); bmp.UnlockBits(d);
      var sb = new System.Text.StringBuilder();
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          int x0 = c*w/cols, x1 = (c+1)*w/cols, y0 = r*h/rows, y1 = (r+1)*h/rows;
          long hit = 0, tot = 0, asum = 0;
          for (int y = y0; y < y1; y += 2) for (int x = x0; x < x1; x += 2) {
            byte a = buf[y*stride + x*4 + 3]; tot++; asum += a; if (a > thresh) hit++;
          }
          double ratio = hit*1.0/Math.Max(1,tot), avg = asum*1.0/Math.Max(1,tot);
          char ch;
          if (ratio > 0.45) ch = '#';
          else if (ratio > 0.20) ch = '+';
          else if (ratio > 0.06) ch = '.';
          else if (avg > 1) ch = ':';
          else ch = ' ';
          sb.Append(ch);
        }
        sb.Append('\n');
      }
      return sb.ToString();
    }
  }
}
"@
Write-Output ([LogoView2]::View($SrcPath, $Cols, $Rows, $Thresh))
