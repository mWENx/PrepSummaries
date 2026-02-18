function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(isoString) {
  const d = new Date(isoString);
  return d.toLocaleString();
}

function renderFiles(result) {
  const list = document.getElementById('file-list');
  list.innerHTML = '';

  if (result?.error) {
    list.innerHTML = `<li class="error">${result.error}</li>`;
    return;
  }

  if (!Array.isArray(result) || result.length === 0) {
    list.innerHTML = '<li class="empty">No generated files found.</li>';
    return;
  }

  result.forEach((file) => {
    const li = document.createElement('li');
    li.className = 'file-row';
    li.dataset.path = file.fullPath;
    li.innerHTML = `
      <span class="file-name" title="${file.fullPath}">${file.name}</span>
      <span>${formatDate(file.modifiedAt)}</span>
      <span>${formatSize(file.sizeBytes)}</span>
    `;
    list.appendChild(li);
  });
}

window.addEventListener('DOMContentLoaded', async () => {
  const files = await window.filesApi.listGenerated();
  renderFiles(files);

  const list = document.getElementById('file-list');
  list.addEventListener('click', async (event) => {
    const row = event.target.closest('.file-row');
    if (!row) return;

    const filePath = row.dataset.path;
    if (!filePath) return;

    const result = await window.filesApi.openPath(filePath);
    if (!result?.ok) {
      window.alert(result?.error || 'Unable to open file.');
    }
  });
});
