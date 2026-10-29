async function reactToImage(event, button) {
  button.disabed = true;
  try {
    const response = await fetch("/react/" + button.dataset.collectionName + "/" + button.dataset.galleryName + "/" + button.dataset.imageName, { method: "POST", body: button.dataset.reaction, headers: {"Content-Type": "text/plain; charset=UTF-8"}});
    if (response.ok) {
      const result = await response.json();
      button.setAttribute("aria-pressed", result.reacted);
      button.querySelector(".count").textContent = result.count;
    }
  }
  catch (error) {
    console.error(error);
  }
  finally {
    button.disabled = false;
  }

}
