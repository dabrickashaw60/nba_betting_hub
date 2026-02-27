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

  function destroyChart(root) {
    if (root && root._playerChart) {
      try {
        root._playerChart.destroy();
      } catch (_) {}
      root._playerChart = null;
    }
  }

  const thresholdLinePlugin = {
    id: "thresholdLine",
    afterDraw(chart, args, opts) {
      const { ctx, chartArea, scales } = chart;
      if (!chartArea) return;

      const y = scales.y.getPixelForValue(opts.value);

      ctx.save();
      ctx.beginPath();
      ctx.moveTo(chartArea.left, y);
      ctx.lineTo(chartArea.right, y);
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.strokeStyle = "rgba(0,0,0,0.4)";
      ctx.stroke();
      ctx.restore();
    }
  };

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
      try {
        return JSON.parse(el.textContent.trim());
      } catch (_) {
        return [];
      }
    };

    const projDefaults = parseJson('[data-role="proj-defaults-json"]') || {};
    const last5 = parseJson('[data-role="games-last5-json"]');
    const last10 = parseJson('[data-role="games-last10-json"]');
    const all = parseJson('[data-role="games-all-json"]');

    const getGamesByRange = () => {
      const v = rangeDropdown.value;
      if (v === "last10") return last10;
      if (v === "all") return all;
      return last5;
    };

    const computeStatData = (games, stat) =>
      games.map((g) => {
        const p = g.points || 0;
        const r = g.rebounds || 0;
        const a = g.assists || 0;
        switch (stat) {
          case "points_assists":
            return p + a;
          case "points_rebounds":
            return p + r;
          case "rebounds_assists":
            return r + a;
          case "points_rebounds_assists":
            return p + r + a;
          default:
            return g[stat] || 0;
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

      // Projection defaults (must be defined above update(), eg:
      // const projDefaults = parseJson('[data-role="proj-defaults-json"]') || {};
      const projectionForStat = (() => {
        const pts = parseFloat(projDefaults.points || 0);
        const reb = parseFloat(projDefaults.rebounds || 0);
        const ast = parseFloat(projDefaults.assists || 0);
        const ths = parseFloat(projDefaults.threes || 0);

        switch (stat) {
          case "points_assists":
            return pts + ast;
          case "points_rebounds":
            return pts + reb;
          case "rebounds_assists":
            return reb + ast;
          case "points_rebounds_assists":
            return pts + reb + ast;
          case "points":
            return pts;
          case "rebounds":
            return reb;
          case "assists":
            return ast;
          case "threes":
            return ths;
          default:
            return null;
        }
      })();

      // 1) compute threshold first (default to projection, fallback to avg)
      let threshold = parseFloat(thresholdInput.value);

      if (Number.isNaN(threshold)) {
        if (projectionForStat != null && !Number.isNaN(parseFloat(projectionForStat))) {
          threshold = Math.round(parseFloat(projectionForStat) * 10) / 10;
        } else {
          threshold = calcAvg(data);
        }
        thresholdInput.value = threshold;
      }

      // 2) now you can color based on threshold
      const barColors = data.map((v) =>
        v >= threshold ? "rgba(25, 135, 84, 0.55)" : "rgba(220, 53, 69, 0.55)"
      );

      const barBorders = data.map((v) =>
        v >= threshold ? "rgba(25, 135, 84, 1)" : "rgba(220, 53, 69, 1)"
      );

      const hits = data.filter((v) => v >= threshold).length;
      const pct = data.length ? Math.round((hits / data.length) * 100) : 0;
      summary.textContent = `Hit rate: ${hits} out of ${data.length} (${pct}%)`;

      const labels = games.map((g) => `${g.date} (${g.opponent})`);

      destroyChart(root);

      root._playerChart = new Chart(canvas.getContext("2d"), {
        type: "bar",
        plugins: [thresholdLinePlugin],
        data: {
          labels: labels,
          datasets: [
            {
              label: stat.replace(/_/g, " ").toUpperCase(),
              data: data,
              backgroundColor: barColors,
              borderColor: barBorders,
              borderWidth: 1
            }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          resizeDelay: 150,
          animation: false,
          plugins: {
            thresholdLine: { value: threshold },
            legend: { display: true }
          },
          scales: {
            y: { beginAtZero: true }
          }
        }
      });
    };

    // Bind controls once
    if (!root._chartControlsBound) {
      root._chartControlsBound = true;

      statDropdown.addEventListener("change", () => {
        thresholdInput.value = "";
        update();
      });

      rangeDropdown.addEventListener("change", () => {
        thresholdInput.value = "";
        update();
      });

      thresholdInput.addEventListener("input", update);
    }

    update();
  }

  function initCharts(root) {
    // No more charts tab. If the chart exists on the page, build it now.
    const canvas = root.querySelector('[data-role="player-line-chart"]');
    if (!canvas) return;

    // Defer by a tick so layout/Bootstrap modal paint is done (prevents 0-height canvas issues)
    window.requestAnimationFrame(() => {
      buildOrUpdateChart(root);
    });
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
        .then((html) => {
          body.innerHTML = html;

          // Optional: charts are based on embedded JSON, which does NOT change here.
          // If you later decide to update chart JSON when filtering, this ensures it redraws.
          initCharts(root);
        })
        .catch(() => alert("An error occurred while fetching filtered games."));
    });

    undoButton.addEventListener("click", () => {
      body.innerHTML = root._lastFiveOriginalHtml;

      // Optional redraw (same note as above)
      initCharts(root);
    });
  }

  function swapModalHeaderFromFrame(frame) {
    const modalHeader = document.getElementById("playerModalHeader");
    if (!modalHeader) return;

    const headerNode = frame.querySelector("[data-player-modal-header]");
    if (!headerNode) return;

    const clone = headerNode.cloneNode(true);
    modalHeader.replaceChildren(clone);
    headerNode.remove();

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
    initCharts(root); // <-- build chart immediately now
  }

  function bindOnce() {
    if (window._playerModalBound) return;
    window._playerModalBound = true;

    log("bound");

    // Load turbo frame when clicking player link
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
        const frame = document.getElementById("player_modal_frame");
        if (frame) {
          const root = frame.querySelector("[data-player-modal-root]");
          if (root) destroyChart(root);
        }
        resetPlayerModal();
      });
    }
  }

  document.addEventListener("turbo:load", bindOnce);
  bindOnce();
})();