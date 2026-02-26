(function () {
  function log() {
    console.log("[player modal]", ...arguments);
  }

  function resetPlayerModal() {
    const frame = document.getElementById("player_modal_frame");
    if (frame) frame.innerHTML = '<div class="p-4 text-muted">Loading...</div>';

    const header = document.getElementById("playerModalHeader");
    if (header) {
      header.innerHTML = `
        <div class="w-100 d-flex align-items-center justify-content-between">
          <div class="text-muted small">Loading...</div>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
      `;
    }
  }

  function initTooltips(root) {
    if (!window.bootstrap) return;
    const tooltipEls = Array.prototype.slice.call(
      root.querySelectorAll('[data-bs-toggle="tooltip"]')
    );
    tooltipEls.forEach((el) => new bootstrap.Tooltip(el));
  }

  function initTeammateFilter(root) {
    const goButton = root.querySelector('[data-role="go-button"]');
    const undoButton = root.querySelector('[data-role="undo-button"]');
    const teammateSelect = root.querySelector('[data-role="teammate-select"]');
    const body = root.querySelector('[data-role="last-five-body"]');
    if (!goButton || !undoButton || !teammateSelect || !body) return;

    if (!root._lastFiveOriginalHtml) root._lastFiveOriginalHtml = body.innerHTML;
    if (root._teammateFilterBound) return;
    root._teammateFilterBound = true;

    goButton.addEventListener("click", () => {
      const teammateId = teammateSelect.value;
      if (!teammateId) return alert("Please select a teammate.");

      const url = goButton.getAttribute("data-filter-url");
      if (!url) return;

      fetch(`${url}?teammate_id=${teammateId}`, {
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })
        .then((r) => (r.ok ? r.text() : Promise.reject(r)))
        .then((html) => { body.innerHTML = html; })
        .catch(() => alert("An error occurred while fetching filtered games."));
    });

    undoButton.addEventListener("click", () => {
      body.innerHTML = root._lastFiveOriginalHtml;
    });
  }

  function buildOrUpdateChart(root) {
    if (!window.Chart) return;

    const canvas = root.querySelector('[data-role="player-line-chart"]');
    const statDropdown = root.querySelector('[data-role="stat-dropdown"]');
    const rangeDropdown = root.querySelector('[data-role="game-range-dropdown"]');
    const thresholdInput = root.querySelector('[data-role="threshold-input"]');
    const summary = root.querySelector('[data-role="hit-rate-summary"]');
    if (!canvas || !statDropdown || !rangeDropdown || !thresholdInput || !summary) return;

    const parseJson = (selector) => {
      const el = root.querySelector(selector);
      if (!el) return [];
      try { return JSON.parse(el.textContent.trim()); } catch (_) { return []; }
    };

    const last5 = parseJson('[data-role="games-last5-json"]');
    const last10 = parseJson('[data-role="games-last10-json"]');
    const all = parseJson('[data-role="games-all-json"]');

    const getGamesByRange = () => {
      const v = rangeDropdown.value;
      if (v === "last10") return last10;
      if (v === "all") return all;
      return last5;
    };

    const computeStatData = (games, stat) => games.map((g) => {
      const p = g.points || 0;
      const r = g.rebounds || 0;
      const a = g.assists || 0;
      switch (stat) {
        case "points_assists": return p + a;
        case "points_rebounds": return p + r;
        case "rebounds_assists": return r + a;
        case "points_rebounds_assists": return p + r + a;
        default: return g[stat] || 0;
      }
    });

    const calcAvg = (arr) => {
      if (!arr.length) return 0;
      const sum = arr.reduce((acc, v) => acc + v, 0);
      return Math.round((sum / arr.length) * 10) / 10;
    };

    const update = () => {
      const games = getGamesByRange();
      const stat = statDropdown.value;
      const data = computeStatData(games, stat);

      let threshold = parseFloat(thresholdInput.value);
      if (Number.isNaN(threshold)) {
        threshold = calcAvg(data);
        thresholdInput.value = threshold;
      }

      const hits = data.filter((v) => v >= threshold).length;
      const pct = data.length ? Math.round((hits / data.length) * 100) : 0;
      summary.textContent = `Hit rate: ${hits} out of ${data.length} (${pct}%)`;

      const labels = games.map((g) => `${g.date} (${g.opponent})`);

      if (root._playerChart) {
        root._playerChart.destroy();
        root._playerChart = null;
      }

      root._playerChart = new Chart(canvas.getContext("2d"), {
        type: "bar",
        data: { labels: labels, datasets: [{ label: stat.replace(/_/g, " ").toUpperCase(), data: data }] },
        options: { responsive: true, scales: { y: { beginAtZero: true } } }
      });
    };

    if (!root._chartControlsBound) {
      root._chartControlsBound = true;

      statDropdown.addEventListener("change", () => { thresholdInput.value = ""; update(); });
      rangeDropdown.addEventListener("change", () => { thresholdInput.value = ""; update(); });
      thresholdInput.addEventListener("input", update);
    }

    update();
  }

  function initCharts(root) {
    const chartsTabBtn = root.querySelector('button[data-bs-target="#player-pane-charts"]');
    if (!chartsTabBtn) return;

    if (root._chartsTabBound) return;
    root._chartsTabBound = true;

    chartsTabBtn.addEventListener("shown.bs.tab", () => {
      buildOrUpdateChart(root);
    });
  }

  function swapModalHeaderFromFrame(frame) {
    const modalHeader = document.getElementById("playerModalHeader");
    if (!modalHeader) return;

    const headerNode = frame.querySelector("[data-player-modal-header]");
    if (!headerNode) return;

    // clone the whole node so we keep classes + inline style vars
    const clone = headerNode.cloneNode(true);

    // replace header contents with the cloned node
    modalHeader.replaceChildren(clone);

    // remove original from the frame so it doesn't show twice
    headerNode.remove();

    // tooltips now live in modal header
    initTooltips(modalHeader);
  }

  function handleFrameLoad(event) {
    const frame = event.target;
    if (!frame || frame.id !== "player_modal_frame") return;

    swapModalHeaderFromFrame(frame);

    const root = frame.querySelector("[data-player-modal-root]");
    if (!root) return;
    

    initTooltips(root);
    initTeammateFilter(root);
    initCharts(root);
  }

  function bindOnce() {
    if (window._playerModalBound) return;
    window._playerModalBound = true;

    log("bound");

    // IMPORTANT: this is what actually loads the frame (bootstrap modal click blocks navigation)
    document.addEventListener("click", function (e) {
      const link = e.target.closest(".player-modal-link");
      if (!link) return;

      const url = link.dataset.playerUrl || link.getAttribute("href");
      const frame = document.getElementById("player_modal_frame");
      if (!frame || !url) return;

      log("click -> frame.src", url);
      frame.src = url;
    });

    document.addEventListener("turbo:frame-load", handleFrameLoad);

    const modalEl = document.getElementById("playerModal");
    if (modalEl) {
      modalEl.addEventListener("hidden.bs.modal", () => {
        // destroy chart to avoid leaks
        const frame = document.getElementById("player_modal_frame");
        if (frame) {
          const root = frame.querySelector("[data-player-modal-root]");
          if (root && root._playerChart) {
            root._playerChart.destroy();
            root._playerChart = null;
          }
        }
        resetPlayerModal();
      });
    }
  }

  document.addEventListener("turbo:load", bindOnce);
  // also run immediately in case turbo:load already fired
  bindOnce();
})();