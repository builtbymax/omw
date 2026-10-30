export const version = '1.0.3';

// The notarized zip of that exact version, so the button keeps working while the site lags behind a release.
export const downloadUrl = `https://github.com/builtbymax/omw/releases/download/v${version}/omw-${version}.zip`;

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
