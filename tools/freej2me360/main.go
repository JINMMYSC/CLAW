//go:build windows

package main

import (
    "archive/zip"
    "bytes"
    "embed"
    "fmt"
    "io"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "syscall"
    "unsafe"
)

//go:embed assets/freej2me_plus.jar assets/temurin17-jre-win64.zip
var assets embed.FS

var (
    user32   = syscall.NewLazyDLL("user32.dll")
    comdlg32 = syscall.NewLazyDLL("comdlg32.dll")
    procMsg  = user32.NewProc("MessageBoxW")
    procOpen = comdlg32.NewProc("GetOpenFileNameW")
)

type openFileName struct {
    lStructSize uint32
    hwndOwner, hInstance uintptr
    lpstrFilter, lpstrCustomFilter *uint16
    nMaxCustFilter, nFilterIndex uint32
    lpstrFile *uint16
    nMaxFile uint32
    lpstrFileTitle *uint16
    nMaxFileTitle uint32
    lpstrInitialDir, lpstrTitle *uint16
    flags uint32
    nFileOffset, nFileExtension uint16
    lpstrDefExt *uint16
    lCustData, lpfnHook, lpTemplateName uintptr
    pvReserved uintptr
    dwReserved, flagsEx uint32
}

const (
    ofnExplorer      = 0x00080000
    ofnFileMustExist = 0x00001000
    ofnPathMustExist = 0x00000800
    ofnNoChangeDir   = 0x00000008
    mbIconError      = 0x10
    mbOK             = 0
)

func u16(s string) *uint16 { p, _ := syscall.UTF16PtrFromString(s); return p }
func message(title, text string, flags uintptr) {
    procMsg.Call(0, uintptr(unsafe.Pointer(u16(text))), uintptr(unsafe.Pointer(u16(title))), flags)
}

func chooseMidlet() string {
    buf := make([]uint16, 32768)
    filter := syscall.StringToUTF16("J2ME games (*.jar;*.jad)\x00*.jar;*.jad\x00JAR files (*.jar)\x00*.jar\x00All files (*.*)\x00*.*\x00\x00")
    ofn := openFileName{
        lStructSize: uint32(unsafe.Sizeof(openFileName{})),
        lpstrFilter: &filter[0],
        nFilterIndex: 1,
        lpstrFile: &buf[0],
        nMaxFile: uint32(len(buf)),
        lpstrTitle: u16("FreeJ2ME 360×360 - 选择游戏"),
        flags: ofnExplorer | ofnFileMustExist | ofnPathMustExist | ofnNoChangeDir,
        lpstrDefExt: u16("jar"),
    }
    r, _, _ := procOpen.Call(uintptr(unsafe.Pointer(&ofn)))
    if r == 0 { return "" }
    return syscall.UTF16ToString(buf)
}

func appDir() string {
    if v := os.Getenv("LOCALAPPDATA"); v != "" { return filepath.Join(v, "FreeJ2ME360Offline") }
    h, _ := os.UserHomeDir()
    return filepath.Join(h, "AppData", "Local", "FreeJ2ME360Offline")
}

func writeEmbeddedFile(name, dest string) error {
    b, err := assets.ReadFile(name)
    if err != nil { return err }
    if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil { return err }
    tmp := dest + ".tmp"
    if err := os.WriteFile(tmp, b, 0644); err != nil { return err }
    _ = os.Remove(dest)
    return os.Rename(tmp, dest)
}

func ensureCore(base string) (string, error) {
    dest := filepath.Join(base, "freej2me_plus.jar")
    if st, err := os.Stat(dest); err == nil && st.Size() > 500000 { return dest, nil }
    if err := writeEmbeddedFile("assets/freej2me_plus.jar", dest); err != nil { return "", err }
    return dest, nil
}

func extractRuntime(base string) (string, error) {
    finalDir := filepath.Join(base, "runtime-17.0.20_8")
    javaw := filepath.Join(finalDir, "bin", "javaw.exe")
    if st, err := os.Stat(javaw); err == nil && !st.IsDir() { return javaw, nil }

    raw, err := assets.ReadFile("assets/temurin17-jre-win64.zip")
    if err != nil { return "", fmt.Errorf("读取内置 Java 运行时失败：%w", err) }
    zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
    if err != nil { return "", fmt.Errorf("内置 Java 压缩包损坏：%w", err) }

    stage := filepath.Join(base, "runtime-stage")
    _ = os.RemoveAll(stage)
    if err := os.MkdirAll(stage, 0755); err != nil { return "", err }

    for _, f := range zr.File {
        clean := filepath.ToSlash(f.Name)
        parts := strings.Split(clean, "/")
        if len(parts) < 2 { continue }
        rel := filepath.FromSlash(strings.Join(parts[1:], "/")) // strip Temurin top-level folder
        if rel == "" || rel == "." { continue }
        out := filepath.Join(stage, rel)
        absStage, _ := filepath.Abs(stage)
        absOut, _ := filepath.Abs(out)
        if absOut != absStage && !strings.HasPrefix(absOut, absStage+string(os.PathSeparator)) {
            return "", fmt.Errorf("Java 压缩包包含非法路径")
        }
        if f.FileInfo().IsDir() {
            if err := os.MkdirAll(out, 0755); err != nil { return "", err }
            continue
        }
        if err := os.MkdirAll(filepath.Dir(out), 0755); err != nil { return "", err }
        rc, err := f.Open(); if err != nil { return "", err }
        dst, err := os.OpenFile(out, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, f.Mode())
        if err != nil { rc.Close(); return "", err }
        _, cpErr := io.Copy(dst, rc)
        closeErr := dst.Close(); rc.Close()
        if cpErr != nil { return "", cpErr }
        if closeErr != nil { return "", closeErr }
    }

    stagedJava := filepath.Join(stage, "bin", "javaw.exe")
    if st, err := os.Stat(stagedJava); err != nil || st.IsDir() {
        return "", fmt.Errorf("Java 解包完成，但没有找到 bin\\javaw.exe")
    }
    _ = os.RemoveAll(finalDir)
    if err := os.Rename(stage, finalDir); err != nil { return "", fmt.Errorf("安装内置 Java 运行时失败：%w", err) }
    return javaw, nil
}

func fileURL(path string) string {
    abs, err := filepath.Abs(path); if err == nil { path = abs }
    p := filepath.ToSlash(path)
    if len(p) >= 2 && p[1] == ':' { return "file:////" + p }
    if strings.HasPrefix(p, "/") { return "file://" + p }
    return "file:///" + p
}

func main() {
    game := ""
    if len(os.Args) > 1 { game = os.Args[1] } else { game = chooseMidlet() }
    if game == "" { return }
    if st, err := os.Stat(game); err != nil || st.IsDir() {
        message("FreeJ2ME 360×360", "找不到所选 J2ME 游戏文件。", mbOK|mbIconError)
        return
    }

    base := appDir()
    if err := os.MkdirAll(base, 0755); err != nil {
        message("FreeJ2ME 360×360", "创建运行目录失败：\n"+err.Error(), mbOK|mbIconError); return
    }
    core, err := ensureCore(base)
    if err != nil { message("FreeJ2ME 360×360", "释放 FreeJ2ME 核心失败：\n"+err.Error(), mbOK|mbIconError); return }
    javaw, err := extractRuntime(base)
    if err != nil { message("FreeJ2ME 360×360", err.Error(), mbOK|mbIconError); return }

    // FreeJ2ME-Plus: path fullscreen width height scale keyLayout framerate dojaversion
    args := []string{"-jar", core, fileURL(game), "0", "360", "360", "1", "0", "60", "10"}
    cmd := exec.Command(javaw, args...)
    cmd.Dir = base
    cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
    if err := cmd.Start(); err != nil {
        message("FreeJ2ME 360×360", "启动失败：\n"+err.Error(), mbOK|mbIconError)
    }
}
