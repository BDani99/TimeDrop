---
name: TimeDrop
colors:
  surface: '#faf9f6'
  surface-dim: '#dbdad7'
  surface-bright: '#faf9f6'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f4f3f1'
  surface-container: '#efeeeb'
  surface-container-high: '#e9e8e5'
  surface-container-highest: '#e3e2e0'
  on-surface: '#1a1c1a'
  on-surface-variant: '#57423d'
  inverse-surface: '#2f312f'
  inverse-on-surface: '#f2f1ee'
  outline: '#8a716c'
  outline-variant: '#dec0b9'
  surface-tint: '#a33d25'
  primary: '#a33d25'
  on-primary: '#ffffff'
  primary-container: '#ff8264'
  on-primary-container: '#731b06'
  inverse-primary: '#ffb4a3'
  secondary: '#7c5637'
  on-secondary: '#ffffff'
  secondary-container: '#fecaa3'
  on-secondary-container: '#795334'
  tertiary: '#a03f30'
  on-tertiary: '#ffffff'
  tertiary-container: '#fb8470'
  on-tertiary-container: '#711d12'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffdad2'
  primary-fixed-dim: '#ffb4a3'
  on-primary-fixed: '#3d0700'
  on-primary-fixed-variant: '#832610'
  secondary-fixed: '#ffdcc3'
  secondary-fixed-dim: '#efbc96'
  on-secondary-fixed: '#2f1500'
  on-secondary-fixed-variant: '#623f22'
  tertiary-fixed: '#ffdad4'
  tertiary-fixed-dim: '#ffb4a7'
  on-tertiary-fixed: '#400200'
  on-tertiary-fixed-variant: '#80281b'
  background: '#faf9f6'
  on-background: '#1a1c1a'
  surface-variant: '#e3e2e0'
typography:
  display-lg:
    fontFamily: Playfair Display
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Playfair Display
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-lg-mobile:
    fontFamily: Playfair Display
    fontSize: 28px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-md:
    fontFamily: Playfair Display
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.4'
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '500'
    lineHeight: '1.4'
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 12px
  md: 24px
  lg: 48px
  xl: 80px
  container-margin: 24px
  gutter: 16px
---

## Brand & Style
The design system is centered on the concept of "Digital Heirloom." It prioritizes emotional resonance over pure utility, evoking the feeling of flipping through a physical photo album at golden hour. The aesthetic is a blend of **Soft Minimalism** and **Tactile Nostalgia**, characterized by warmth, breathability, and an approachable elegance.

The target audience consists of sentimental storytellers and families who value depth and privacy. The UI should evoke a sense of calm and safety, using soft transitions and organic depth to make the digital space feel like a curated, cozy physical environment.

## Colors
The palette is inspired by the "Golden Hour"—the transition between day and dusk. 

- **Primary & Secondary:** Sunset Orange and Peach are used for primary actions and brand moments, providing a glow that guides the user's eye.
- **Background:** The Cream base (#FAF9F6) is essential for avoiding the clinical feel of pure white, providing a soft, paper-like foundation.
- **Accents:** Warm Terracotta is reserved for high-emphasis alerts or deep tonal contrast, while Rose Gold is used for delicate highlights and borders.
- **Contrast:** Text should never be pure black; use a deep, warm chocolate brown (#3D2B27) to maintain the nostalgic, organic feel.

## Typography
The typography strategy relies on the high-contrast pairing of a classic serif with a contemporary, soft sans-serif.

- **Headlines:** Playfair Display provides a literary, editorial feel. Use it for memory titles, dates, and major section headers. It should feel authoritative yet romantic.
- **Body & Labels:** Plus Jakarta Sans was chosen over Inter for its slightly more rounded terminals and friendly apertures, which better complement the organic nature of the brand. 
- **Hierarchy:** Maintain generous line heights (1.6 for body) to ensure a relaxed reading pace, reflecting the "slow" nature of memory-sharing.

## Layout & Spacing
The layout follows a **Fluid Content Model** with intentional "breathable" gaps. 

- **Grid:** Use a 12-column grid for desktop and a 4-column grid for mobile. 
- **Rhythm:** Avoid tight clusters. Content groups should be separated by at least `md` (24px) spacing. 
- **Negative Space:** Use "white space" as a functional element to isolate memories, preventing the UI from feeling cluttered. Full-bleed imagery is encouraged for memory views to create an immersive, tactile experience.
- **Breakpoints:** 
  - Mobile: 0px - 599px (Margins: 24px)
  - Tablet: 600px - 1023px (Margins: 40px)
  - Desktop: 1024px+ (Margins: Auto, max-width 1200px)

## Elevation & Depth
Depth in this design system is achieved through **Pillowy Volume** rather than sharp shadows.

- **Surface Tiers:** Use subtle background shifts from Cream (#FAF9F6) to a slightly darker Peach-tinted neutral to denote hierarchy.
- **Shadows:** Avoid harsh, grey shadows. Use "Ambient Glow" shadows—low opacity (10-15%), large blur (30px-50px), and tinted with the primary Sunset Orange or Terracotta. This creates the illusion that elements are floating softly above a warm light source.
- **Organic Blurs:** Incorporate "Bokeh" elements—large, semi-transparent blurred circles of Peach and Rose Gold—in the background to add depth and a sense of "captured light."

## Shapes
Shapes are exceptionally soft and organic. 

- **Corners:** The standard radius for cards and containers is 24px+. For small UI elements like buttons, use the Pill-shape (fully rounded) to maximize the friendly, non-threatening feel.
- **Interactions:** Hover states should involve "squishy" scaling (e.g., scale(1.02)) to reinforce the tactile, physical metaphor.
- **Lines:** Use ultra-thin (1px) strokes in Rose Gold or light Peach for separators to maintain a delicate, elegant appearance.

## Components
- **Buttons:** Large, pill-shaped, and high-contrast. The primary button uses a Sunset Orange gradient with white text. Secondary buttons should be ghost-style with a Rose Gold border.
- **Cards:** Use the "Memory Card" pattern: 32px rounded corners, ambient orange-tinted shadows, and a 1px Rose Gold border. Images within cards should have a slightly smaller radius (24px) to create a "nested" look.
- **Inputs:** Soft, off-white fills with 16px rounded corners. The focus state should glow with a soft Peach outer shadow rather than a hard border change.
- **Chips/Tags:** Use for categorizing memories (e.g., "Family," "2023"). These should be pill-shaped with light Peach backgrounds and Terracotta text.
- **Icons:** Use thin-stroke (1.5px) icons with rounded ends. Avoid sharp corners or filled-in styles unless the icon is in an active state.
- **Progress Indicators:** Use soft, fluid "blob" transitions or thin, elegant lines for loading states to maintain the calm atmosphere.