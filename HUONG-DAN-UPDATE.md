# Hướng Dẫn Cập Nhật CLIProxyAPI

## Cập Nhật Thủ Công (Windows)

### Bước 1: Mở PowerShell
- Click chuột phải vào thư mục project
- Chọn "Open in Terminal" hoặc "Open PowerShell window here"

### Bước 2: Chạy script
```powershell
.\auto-update.ps1
```

### Kết quả
- **Có update**: Script sẽ tự động merge, rebuild Docker và restart container
- **Không có update**: Hiển thị "Already up to date!" và dừng lại

---

## Cập Nhật Tự Động (GitHub Actions)

Workflow đã được cấu hình chạy **mỗi 6 giờ** tự động sync từ upstream.

### Trigger thủ công trên GitHub:
1. Vào https://github.com/pdtkts/CLIProxyAPI
2. Click tab **Actions**
3. Chọn **"Sync with Upstream"**
4. Click **"Run workflow"** → **"Run workflow"**

---

## Commands Riêng Lẻ

```powershell
# Kiểm tra có update không
git fetch upstream
git log --oneline HEAD..upstream/main

# Merge update
git merge upstream/main --no-edit
git push origin main

# Rebuild Docker
docker-compose build --no-cache
docker-compose down
docker-compose up -d

# Xem logs
docker logs cli-proxy-api-plus --tail 30
```

---

## Xử Lý Lỗi

### Lỗi merge conflict
```powershell
git merge --abort
git reset --hard origin/main
git pull upstream main --rebase
git push origin main --force
```

### Lỗi Docker build
```powershell
docker system prune -f
docker-compose build --no-cache
```

---

## Upstream Repository
https://github.com/router-for-me/CLIProxyAPIPlus
