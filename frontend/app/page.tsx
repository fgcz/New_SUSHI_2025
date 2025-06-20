import Image from 'next/image';
import Link from 'next/link';

// Define the type for a menu item
interface MenuItem {
  title: string;
  description: string;
  link: string;
  icon: string;
}

// Array of menu items based on the analysis of the old system
const menuItems: MenuItem[] = [
  {
    title: 'DataSets',
    description: 'You can see, edit and delete DataSets.\nYou can execute a SUSHI application.',
    link: '/datasets', // Placeholder link
    icon: '/images/tamago.png',
  },
  {
    title: 'Import DataSet',
    description: 'Import a DataSet from .tsv file.',
    link: '/import', // Placeholder link
    icon: '/images/tako.png',
  },
  {
    title: 'Check Jobs',
    description: 'Check your submitted jobs and the status.',
    link: '/jobs', // Placeholder link
    icon: '/images/maguro.png',
  },
  {
    title: 'gStore',
    description: 'Show result folder. You can see and download files of result data.',
    link: '/gstore', // Placeholder link
    icon: '/images/uni.png',
  },
];

// A component for a single menu card
// The description is split by newline characters to render <br /> tags
const MenuCard = ({ item }: { item: MenuItem }) => (
  <div className="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow duration-300 ease-in-out border border-gray-200">
    <Link href={item.link} className="block p-6 text-center">
      <div className="flex flex-col items-center">
        <div className="w-32 h-32 relative mb-4">
            <Image src={item.icon} alt={`${item.title} icon`} fill className="object-contain" />
        </div>
        <h3 className="text-xl font-semibold text-blue-700 mb-2">{item.title}</h3>
        <p className="text-gray-600 text-sm">
            {item.description.split('\n').map((line, index) => (
              <span key={index}>{line}{index !== item.description.split('\n').length - 1 && <br />}</span>
            ))}
        </p>
      </div>
    </Link>
  </div>
);

// The main dashboard page component, replacing the existing Home component
export default function Home() {
  const projectNumber = 38222; // Hardcoded project number as in the screenshot
  const userName = "masaomi"; // Hardcoded user name

  return (
    <div className="flex flex-col min-h-screen" style={{ backgroundColor: '#e0e5e9' }}>
      <header className="bg-white shadow-sm border-b-2 border-gray-200">
        <div className="container mx-auto px-6 py-3 flex justify-between items-center">
          <h1 className="text-3xl font-bold" style={{fontFamily: "Comic Sans MS, cursive, sans-serif"}}>Sushi</h1>
          <nav className="flex items-center space-x-4">
            <Link href="/datasets" className="text-gray-600 hover:text-blue-600">DataSets</Link>
            <Link href="/import" className="text-gray-600 hover:text-blue-600">Import</Link>
            <Link href="/jobs" className="text-gray-600 hover:text-blue-600">Jobs</Link>
            <Link href="/gstore" className="text-gray-600 hover:text-blue-600">gStore</Link>
            <Link href="/help" className="text-gray-600 hover:text-blue-600">Help</Link>
            <div className="border-l border-gray-300 h-6"></div>
            <span className="font-semibold">Project {projectNumber}</span>
            <span className="text-gray-700">Hi, {userName} | <Link href="/logout" className="text-blue-600 hover:underline">Sign out</Link></span>
          </nav>
        </div>
      </header>

      <main className="flex-grow container mx-auto px-6 py-10">
        <div className="bg-white p-8 rounded-lg shadow-inner" style={{ backgroundColor: 'rgba(255, 255, 255, 0.8)' }}>
            <h2 className="text-3xl font-bold text-gray-800 mb-8">
              Project {projectNumber}
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-8">
              {menuItems.map((item) => (
                <MenuCard key={item.title} item={item} />
              ))}
            </div>
        </div>
      </main>

      <footer className="py-4 mt-auto" style={{ backgroundColor: '#2c3e50', color: 'white' }}>
        <div className="container mx-auto px-6 text-center text-sm">
          SUSHI - produced by Functional Genomics Center Zurich and SIB
        </div>
      </footer>
    </div>
  );
}
