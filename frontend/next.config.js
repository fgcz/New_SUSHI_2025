/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: 'http://fgcz-h-037.fgcz-net.unizh.ch:4000/api/:path*',
      },
    ];
  },
};

module.exports = nextConfig; 