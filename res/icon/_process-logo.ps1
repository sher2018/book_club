# process-logo.ps1 — logo 背景透明化 + 裁剪留白 + 方形透明画布
# 用法: powershell -File process-logo.ps1 <源图> <输出master>
param(
  [Parameter(Mandatory=$true)][string]$SrcPath,
  [Parameter(Mandatory=$true)][string]$OutPath
)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class LogoProcessor {
  public static string Process(string srcPath, string outPath, int t1, int t2, int alphaThresh, double marginRatio) {
    using (Bitmap src = new Bitmap(srcPath)) {
      int w = src.Width, h = src.Height;
      Rectangle rect = new Rectangle(0, 0, w, h);
      BitmapData data = src.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      int bytes = Math.Abs(data.Stride) * h;
      byte[] buf = new byte[bytes];
      Marshal.Copy(data.Scan0, buf, 0, bytes);
      int stride = data.Stride;
      src.UnlockBits(data);

      const double bgR = 255, bgG = 255, bgB = 255;
      int minX = w, minY = h, maxX = -1, maxY = -1;
      long opaqueCount = 0;

      for (int y = 0; y < h; y++) {
        int row = y * stride;
        for (int x = 0; x < w; x++) {
          int i = row + x * 4;
          double a0 = buf[i + 3] / 255.0;
          double fr = buf[i + 2] * a0 + bgR * (1 - a0);
          double fg = buf[i + 1] * a0 + bgG * (1 - a0);
          double fb = buf[i]     * a0 + bgB * (1 - a0);
          double dist = Math.Sqrt((fr - bgR) * (fr - bgR) + (fg - bgG) * (fg - bgG) + (fb - bgB) * (fb - bgB));
          double a = (dist - t1) / (double)(t2 - t1);
          if (a < 0) a = 0; if (a > 1) a = 1;
          byte A = (byte)Math.Round(a * 255);
          double nr = fr, ng = fg, nb = fb;
          if (A > 0) {
            double af = A / 255.0;
            nr = (fr - bgR * (1 - af)) / af;
            ng = (fg - bgG * (1 - af)) / af;
            nb = (fb - bgB * (1 - af)) / af;
          }
          buf[i]     = (byte)Math.Max(0, Math.Min(255, Math.Round(nb)));
          buf[i + 1] = (byte)Math.Max(0, Math.Min(255, Math.Round(ng)));
          buf[i + 2] = (byte)Math.Max(0, Math.Min(255, Math.Round(nr)));
          buf[i + 3] = A;
          if (A > alphaThresh) {
            if (x < minX) minX = x; if (y < minY) minY = y;
            if (x > maxX) maxX = x; if (y > maxY) maxY = y;
            opaqueCount++;
          }
        }
      }
      if (maxX < 0) return "EMPTY";
      int bw = maxX - minX + 1, bh = maxY - minY + 1;
      int m = (int)Math.Ceiling(Math.Max(bw, bh) * marginRatio);
      minX = Math.Max(0, minX - m); minY = Math.Max(0, minY - m);
      maxX = Math.Min(w - 1, maxX + m); maxY = Math.Min(h - 1, maxY + m);
      bw = maxX - minX + 1; bh = maxY - minY + 1;

      using (Bitmap proc = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
        BitmapData pd = proc.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(buf, 0, pd.Scan0, bytes);
        proc.UnlockBits(pd);
        int side = Math.Max(bw, bh);
        using (Bitmap outBmp = new Bitmap(side, side, PixelFormat.Format32bppArgb)) {
          using (Graphics g = Graphics.FromImage(outBmp)) {
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
            g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
            int ox = (side - bw) / 2, oy = (side - bh) / 2;
            g.DrawImage(proc, new Rectangle(ox, oy, bw, bh), new Rectangle(minX, minY, bw, bh), GraphicsUnit.Pixel);
          }
          outBmp.Save(outPath, ImageFormat.Png);
        }
      }
      double opaqueRatio = opaqueCount / (double)(w * h);
      return string.Format("OK bbox=({0},{1})-({2},{3}) content={4}x{5} side={6} opaqueRatio={7:F3}",
        minX, minY, maxX, maxY, bw, bh, Math.Max(bw, bh), opaqueRatio);
    }
  }
}
"@
$result = [LogoProcessor]::Process($SrcPath, $OutPath, 15, 100, 10, 0.015)
Write-Output $result
if ($result -eq "EMPTY") { exit 1 }
