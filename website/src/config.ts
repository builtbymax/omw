// The GitHub repo is private for now, so release downloads need a login.
// Point this at a public URL (the zip Sparkle's appcast references) once there is one.
export const downloadUrl = 'https://github.com/builtbymax/omw/releases/latest';

export const version = '0.2.0';
export const minimumMacOS = '14';
export const domain = 'omw.halftime.space';
export const brewCommand = 'brew install --cask builtbymax/tap/omw';
export const contactEmail = 'omw@halftime.space';

// Legal notice (Impressum) on the contact page. Fill in before going live.
export const legal = {
  name: '[Full name]',
  street: '[Street and number]',
  city: '[Postcode and city]',
  country: '[Country]',
};

export const githubUrl = 'https://github.com/builtbymax/omw';

export const footerLinks = [
  { label: 'Privacy', href: '/privacy' },
  { label: 'Contact', href: '/contact' },
  { label: 'GitHub', href: githubUrl },
];
