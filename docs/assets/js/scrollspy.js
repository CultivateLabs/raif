document.addEventListener('DOMContentLoaded', function() {
  const toc = document.getElementById('markdown-toc');
  
  if (!toc) return;
  
  // Only create scrollspy TOC on wider screens
  const windowWidth = window.innerWidth;
  if (windowWidth < 1400) {
    return; // Keep original TOC on smaller screens
  }
  
  // Create wrapper for the TOC
  const tocWrapper = document.createElement('div');
  tocWrapper.className = 'toc-wrapper';
  tocWrapper.id = 'toc-wrapper';
  
  // Create inner container for proper scrolling
  const tocInner = document.createElement('div');
  tocInner.className = 'toc-inner';
  
  // Move TOC into the wrapper
  const tocClone = toc.cloneNode(true);
  tocInner.appendChild(tocClone);
  tocWrapper.appendChild(tocInner);
  
  // Add title
  const tocTitle = document.getElementById('table-of-contents');
  // Hide the a.anchor-heading inside the tocTitle (if present)
  if (tocTitle) {
    const anchor = tocTitle.querySelector('a.anchor-heading');
    if (anchor) {
      anchor.style.display = 'none';
    }
  }
  tocWrapper.insertBefore(tocTitle, tocInner);
  
  // Insert the wrapper into the body (not main-content)
  document.body.appendChild(tocWrapper);
  
  // Hide original TOC only if we successfully created the new one
  toc.style.display = 'none';
  
  // Get all headers that are in the TOC
  const tocLinks = tocWrapper.querySelectorAll('a');
  const headerIds = Array.from(tocLinks).map(link => {
    const href = link.getAttribute('href');
    return href ? href.substring(1) : null;
  }).filter(id => id);
  
  const headers = headerIds.map(id => document.getElementById(id)).filter(h => h);
  
  // Scrollspy functionality
  function updateActiveLink() {
    const scrollPosition = window.pageYOffset || document.documentElement.scrollTop;
    const windowHeight = window.innerHeight;
    const documentHeight = document.documentElement.scrollHeight;
    
    // Check if we're at the bottom of the page
    const isAtBottom = scrollPosition + windowHeight >= documentHeight - 10;
    
    let currentHeader = null;
    
    if (isAtBottom && headers.length > 0) {
      // If at bottom, highlight the last header
      currentHeader = headers[headers.length - 1];
    } else {
      // Find the current header based on scroll position
      for (let i = headers.length - 1; i >= 0; i--) {
        const header = headers[i];
        const headerTop = header.getBoundingClientRect().top + scrollPosition;
        
        // Add offset to account for fixed headers
        if (scrollPosition >= headerTop - 100) {
          currentHeader = header;
          break;
        }
      }
    }
    
    // Update active states
    tocLinks.forEach(link => {
      link.classList.remove('active');
      const linkHref = link.getAttribute('href');
      if (currentHeader && linkHref === '#' + currentHeader.id) {
        link.classList.add('active');
        
        // Ensure the active link is visible in the TOC
        const tocInner = tocWrapper.querySelector('.toc-inner');
        const linkRect = link.getBoundingClientRect();
        const tocRect = tocInner.getBoundingClientRect();
        
        if (linkRect.top < tocRect.top || linkRect.bottom > tocRect.bottom) {
          link.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }
    });
  }
  
  // Smooth scrolling for TOC links
  tocLinks.forEach(link => {
    link.addEventListener('click', function(e) {
      e.preventDefault();
      const targetId = this.getAttribute('href').substring(1);
      const targetElement = document.getElementById(targetId);
      
      if (targetElement) {
        const headerOffset = 80; // Adjust based on your header height
        const elementPosition = targetElement.getBoundingClientRect().top;
        const offsetPosition = elementPosition + window.pageYOffset - headerOffset;
        
        window.scrollTo({
          top: offsetPosition,
          behavior: 'smooth'
        });
        
        // Update URL without jumping
        if (history.pushState) {
          history.pushState(null, null, '#' + targetId);
        }
      }
    });
  });
  
  // Throttle scroll events for performance
  let scrollTimeout;
  function handleScroll() {
    if (scrollTimeout) {
      window.cancelAnimationFrame(scrollTimeout);
    }
    scrollTimeout = window.requestAnimationFrame(updateActiveLink);
  }
  
  // Listen for scroll events
  window.addEventListener('scroll', handleScroll);
  window.addEventListener('resize', updateActiveLink);
  
  // Initial update
  updateActiveLink();
  
  // Handle responsive behavior
  function checkTocVisibility() {
    const windowWidth = window.innerWidth;
    if (windowWidth < 1400) {
      tocWrapper.style.display = 'none';
      toc.style.display = 'block'; // Show original TOC on smaller screens
    } else {
      tocWrapper.style.display = 'block';
      toc.style.display = 'none'; // Hide original TOC on larger screens
    }
  }
  
  window.addEventListener('resize', checkTocVisibility);
  checkTocVisibility();
});