document.addEventListener("turbo:load", () => {
  const searchInput = document.querySelector("#playerSearchInput");
  const resultsContainer = document.querySelector("#liveSearchResults");

  if (searchInput && resultsContainer) {
    searchInput.addEventListener("input", () => {
      const query = searchInput.value.trim();

      if (query.length > 0) {
        fetch(`/players/live_search?query=${encodeURIComponent(query)}`)
          .then(response => response.json())
          .then(players => {
            // Clear previous results
            resultsContainer.innerHTML = "";

            // If there are players, display them
            if (players.length > 0) {
              players.forEach(player => {
                const playerLink = document.createElement("a");
                playerLink.href = `/teams/${player.team.id}/players/${player.id}`;
                playerLink.classList.add("list-group-item", "list-group-item-action", "d-flex", "align-items-center");

                // Disable Turbo for the link
                playerLink.setAttribute("data-turbo", "false");

                // Construct team logo URL
                const teamLogoUrl = `https://cdn.ssref.net/req/202410231/tlogo/bbr/${player.team.abbreviation}-2025.png`;

                // Add logo image
                const logoImg = document.createElement("img");
                logoImg.src = teamLogoUrl;
                logoImg.alt = `${player.team.name} logo`;
                logoImg.width = 20;
                logoImg.height = 20;
                logoImg.classList.add("me-2");

                // Append logo and player name to link
                playerLink.appendChild(logoImg);
                playerLink.insertAdjacentText("beforeend", `${player.name}`);

                resultsContainer.appendChild(playerLink);
              });
              resultsContainer.style.display = "block";
            } else {
              // Hide the container if no results
              resultsContainer.style.display = "none";
            }
          });
      } else {
        resultsContainer.innerHTML = "";
        resultsContainer.style.display = "none";
      }
    });

    // Hide the results when clicking outside the input or results container
    document.addEventListener("click", (event) => {
      if (!resultsContainer.contains(event.target) && event.target !== searchInput) {
        resultsContainer.style.display = "none";
      }
    });
  }
});
