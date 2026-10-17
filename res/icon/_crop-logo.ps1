# _crop-logo.ps1 - alpha-threshold based bbox analyze + pure crop (no color change)
# Analyze: print content bbox at several alpha thresholds
# Crop:    crop by threshold + margin ratio, center onto square transparent canvas
#          ExclX/ExclY: ignore pixels with x>=ExclX or y>=ExclY when computing bbox
param(
  [Parameter(Mandatory=$true)][string]$SrcPath,
  [string]$OutPath,
  [int]$AlphaThresh = 32,
  [double]$MarginRatio = 0.0,
  [int]$ExclX = -1,
  [int]$ExclY = -1,
  [switch]$AnalyzeOnly
)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class LogoCrop3 {
  static byte[] LoadData(string path, out int w, out int h, out int stride) {
    using (Bitmap bmp = new Bitmap(path)) {
      w = bmp.Width; h = bmp.Height;
      Rectangle rect = new Rectangle(0, 0, w, h);
      BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      stride = data.Stride;
      byte[] buf = new byte[Math.Abs(stride) * h];
      Marshal.Copy(data.Scan0, buf, 0, buf.Length);
      bmp.UnlockBits(data);
      return buf;
    }
  }

  static int[] BBox(byte[] buf, int w, int h, int stride, int thresh, int exclX, int exclY) {
    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (int y = 0; y < h; y++) {
      if (exclY >= 0 && y >= exclY) continue;
      int row = y * stride;
      for (int x = 0; x < w; x++) {
        if (exclX >= 0 && x >= exclX) continue;
        if (buf[row + x * 4 + 3] > thresh) {
          if (x < minX) minX = x; if (y < minY) minY = y;
          if (x > maxX) maxX = x; if (y > maxY) maxY = y;
        }
      }
    }
    return new int[] { minX, minY, maxX, maxY };
  }

  public static string Analyze(string path) {
    int w, h, stride;
    byte[] buf = LoadData(path, out w, out h, out stride);
    var sb = new System.Text.StringBuilder();
    foreach (int t in new int[] { 0, 8, 16, 32, 64, 96, 128 }) {
      int[] b = BBox(buf, w, h, stride, t, -1, -1);
      if (b[2] < 0) { sb.AppendFormat("t={0}: EMPTY\n", t); continue; }
      int bw = b[2] - b[0] + 1, bh = b[3] - b[1] + 1;
      sb.AppendFormat("t={0}: bbox=({1},{2})-({3},{4}) content={5}x{6}\n", t, b[0], b[1], b[2], b[3], bw, bh);
    }
    return sb.ToString();
  }

  public static string Crop(string srcPath, string outPath, int thresh, double marginRatio, int exclX, int exclY) {
    int w, h, stride;
    byte[] buf = LoadData(srcPath, out w, out h, out stride);
    int[] b = BBox(buf, w, h, stride, thresh, exclX, exclY);
    if (b[2] < 0) return "EMPTY";
    int minX = b[0], minY = b[1], maxX = b[2], maxY = b[3];
    int bw = maxX - minX + 1, bh = maxY - minY + 1;
    int m = (int)Math.Ceiling(Math.Max(bw, bh) * marginRatio);
    minX = Math.Max(0, minX - m); minY = Math.Max(0, minY - m);
    maxX = Math.Min(w - 1, maxX + m); maxY = Math.Min(h - 1, maxY + m);
    bw = maxX - minX + 1; bh = maxY - minY + 1;

    using (Bitmap src = new Bitmap(srcPath))
    using (Bitmap outBmp = new Bitmap(Math.Max(bw, bh), Math.Max(bw, bh), PixelFormat.Format32bppArgb)) {
      using (Graphics g = Graphics.FromImage(outBmp)) {
        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
        g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
        int side = Math.Max(bw, bh);
        g.DrawImage(src, new Rectangle((side - bw) / 2, (side - bh) / 2, bw, bh),
                    new Rectangle(minX, minY, bw, bh), GraphicsUnit.Pixel);
      }
      outBmp.Save(outPath, ImageFormat.Png);
    }
    return string.Format("OK crop bbox=({0},{1})-({2},{3}) content={4}x{5} side={6} margin={7}px",
      minX, minY, maxX, maxY, bw, bh, Math.Max(bw, bh), m);
  }
}
"@
if ($AnalyzeOnly) {
  Write-Output ([LogoCrop3]::Analyze($SrcPath))
} else {
  $result = [LogoCrop3]::Crop($SrcPath, $OutPath, $AlphaThresh, $MarginRatio, $ExclX, $ExclY)
  Write-Output $result
  if ($result -eq "EMPTY") { exit 1 }
}
