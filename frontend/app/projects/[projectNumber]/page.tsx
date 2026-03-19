'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import Breadcrumbs from '@/lib/ui/Breadcrumbs';

// Define the type for a menu item
interface MenuItem {
  title: string;
  description: string;
  link: string;
  icon: string;
}

// A component for a single menu card
// The description is split by newline characters to render <br /> tags
const MenuCard = ({ item }: { item: MenuItem }) => (
  <div className="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow duration-300 ease-in-out border border-gray-200">
    <Link href={item.link} className="block p-6 text-center">
      <div className="flex flex-col items-center">
        <div className="w-32 h-32 relative mb-4">
            <Image src={item.icon} alt={`${item.title} icon`} fill sizes="128px" className="object-contain" />
        </div>
        <h3 className="text-xl font-semibold text-brand-700 mb-2">{item.title}</h3>
        <p className="text-gray-600 text-xs">
            {item.description.split('\n').map((line, index) => (
              <span key={index}>{line}{index !== item.description.split('\n').length - 1 && <br />}</span>
            ))}
        </p>
      </div>
    </Link>
  </div>
);

// The main project dashboard page component
export default function ProjectPage() {
  const params = useParams<{ projectNumber: string }>();
  const projectNumber = Number(params.projectNumber);

  const menuItems: MenuItem[] = [
    {
      title: 'DataSets',
      description: 'You can see, edit and delete DataSets.\nYou can execute a SUSHI application.',
      link: `/projects/${projectNumber}/datasets`,
      icon: '/images/tamago.png',
    },
    {
      title: 'Import DataSet',
      description: 'Import a DataSet from .tsv file.',
      link: `/projects/${projectNumber}/datasets/import`,
      icon: '/images/tako.png',
    },
    {
      title: 'Check Jobs',
      description: 'Check your submitted jobs and the status.',
      link: `/projects/${projectNumber}/jobs`,
      icon: '/images/maguro.png',
    },
    {
      title: 'gStore',
      description: 'Show result folder. You can see and download files of result data.',
      link: `files/p${projectNumber}`,
      icon: '/images/uni.png',
    },
  ];

  return (
    <div className="container mx-auto px-6 py-10">
      {/*<Breadcrumbs items={[
        { label: 'Projects', href: '/projects' },
        { label: `Project ${projectNumber}`, active: true }
      ]} />*/}
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
    </div>
  );
}
