# progress.md — cemoy-it-h2-plan

## 当前状态

| 项 | 状态 |
|----|------|
| 正式版 HTML | ✅ 已按最新口径定稿 |
| GitHub Pages | ✅ 已发布（公开仓库） |
| 隧道 | ❌ 已停用并清理 |

## 外网访问（Git 免费域名，非隧道）

- **GitHub Pages**：https://harry-hanyu.github.io/cemoy-it-h2-plan/
- **仓库**：https://github.com/Harry-hanyu/cemoy-it-h2-plan
- **国内 CDN 镜像（jsDelivr）**：https://cdn.jsdelivr.net/gh/Harry-hanyu/cemoy-it-h2-plan@main/index.html

## 预算速记

- **不含人力**（影刀年费 4 万计入）：约 **8.3～9.3 万** / 半年  
- **含人力全部**：约 **19.1～21.3 万** / 半年  

## 更新发布

```bash
bash ~/Projects/cemoy-it-h2-plan/scripts/publish-pages.sh
```

改 `docs/IT半年度工作规划-正式版.html` → 脚本同步到 `index.html` 并 push → Pages 约 1～2 分钟生效。
