document.addEventListener('DOMContentLoaded', () => {
    const downloadForm = document.getElementById('downloadForm');
    const urlInput = document.getElementById('urlInput');
    const pasteBtn = document.getElementById('pasteBtn');
    const submitBtn = document.getElementById('submitBtn');
    const loadingState = document.getElementById('loadingState');
    const errorState = document.getElementById('errorState');
    const errorMessage = document.getElementById('errorMessage');
    const resultCard = document.getElementById('resultCard');

    const mediaThumbnail = document.getElementById('mediaThumbnail');
    const mediaDuration = document.getElementById('mediaDuration');
    const mediaPlatform = document.getElementById('mediaPlatform');
    const mediaUploader = document.getElementById('mediaUploader');
    const mediaTitle = document.getElementById('mediaTitle');
    const formatsList = document.getElementById('formatsList');

    // Clipboard Paste Handler
    if (pasteBtn) {
        pasteBtn.addEventListener('click', async () => {
            try {
                const text = await navigator.clipboard.readText();
                if (text) {
                    urlInput.value = text;
                }
            } catch (err) {
                console.warn('Gagal membaca clipboard:', err);
            }
        });
    }

    // Form Submit Handler
    downloadForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const url = urlInput.value.trim();

        if (!url) {
            showError('Masukkan URL media sosial yang valid.');
            return;
        }

        resetUI();
        showLoading(true);

        try {
            const response = await fetch('/api/extract', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ url })
            });

            const result = await response.json();

            if (!response.ok) {
                throw new Error(result.detail || 'Terjadi kesalahan saat memproses media.');
            }

            renderMediaResult(result.data);
        } catch (err) {
            showError(err.message || 'Gagal terhubung ke server.');
        } finally {
            showLoading(false);
        }
    });

    function showLoading(isLoading) {
        if (isLoading) {
            loadingState.classList.remove('hidden');
            submitBtn.disabled = true;
            submitBtn.classList.add('opacity-75', 'cursor-not-allowed');
        } else {
            loadingState.classList.add('hidden');
            submitBtn.disabled = false;
            submitBtn.classList.remove('opacity-75', 'cursor-not-allowed');
        }
    }

    function showError(msg) {
        errorMessage.textContent = msg;
        errorState.classList.remove('hidden');
    }

    function resetUI() {
        errorState.classList.add('hidden');
        resultCard.classList.add('hidden');
        formatsList.innerHTML = '';
    }

    function renderMediaResult(data) {
        mediaTitle.textContent = data.title || 'Media Social';
        mediaThumbnail.src = data.thumbnail || 'https://via.placeholder.com/400x225?text=No+Thumbnail';
        mediaDuration.textContent = data.duration || 'N/A';
        mediaPlatform.textContent = data.platform || 'Social Media';
        mediaUploader.textContent = `@${data.uploader || 'User'}`;

        formatsList.innerHTML = '';

        if (!data.formats || data.formats.length === 0) {
            formatsList.innerHTML = '<p class="text-xs text-slate-400">Tidak ada format yang dapat diunduh langsung.</p>';
            resultCard.classList.remove('hidden');
            return;
        }

        data.formats.forEach((fmt) => {
            const btn = document.createElement('a');
            const safeTitle = (data.title || 'media').replace(/[^a-zA-Z0-9_\-]/g, '_');
            const downloadFilename = `${safeTitle}_${fmt.quality.replace(/\s+/g, '_')}.${fmt.ext}`;
            const directProxyUrl = `/api/download?url=${encodeURIComponent(fmt.url)}&filename=${encodeURIComponent(downloadFilename)}`;

            btn.href = directProxyUrl;
            btn.target = '_blank';
            btn.className = 'flex items-center justify-between p-3 bg-slate-800/60 hover:bg-blue-600/20 border border-slate-700/60 hover:border-blue-500/50 rounded-xl transition-all group';

            const iconClass = fmt.type === 'audio' ? 'fa-music' : 'fa-video';
            const iconColor = fmt.type === 'audio' ? 'text-amber-400' : 'text-blue-400';

            btn.innerHTML = `
                <div class="flex items-center gap-2.5 overflow-hidden">
                    <div class="w-8 h-8 rounded-lg bg-slate-900 border border-slate-700/50 flex items-center justify-center ${iconColor} flex-shrink-0">
                        <i class="fa-solid ${iconClass} text-xs"></i>
                    </div>
                    <div class="truncate text-left">
                        <div class="text-xs font-bold text-white group-hover:text-blue-300 transition-colors truncate">
                            ${fmt.quality}
                        </div>
                        <div class="text-[10px] text-slate-400">
                            Ukuran: ${fmt.filesize || 'N/A'}
                        </div>
                    </div>
                </div>
                <div class="flex items-center gap-1 text-xs font-semibold text-blue-400 group-hover:text-blue-300 pl-2 flex-shrink-0">
                    <span>Unduh</span>
                    <i class="fa-solid fa-download text-xs group-hover:translate-y-0.5 transition-transform"></i>
                </div>
            `;

            formatsList.appendChild(btn);
        });

        resultCard.classList.remove('hidden');
        resultCard.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
});
