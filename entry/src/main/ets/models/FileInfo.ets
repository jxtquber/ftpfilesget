export class FileInfo {
  name: string = '';
  path: string = '';
  isDirectory: boolean = false;
  size: number = 0;
  modificationTime: number = 0;
}

export enum FileType {
  Folder = 'folder',
  Markdown = 'markdown',
  Image = 'image',
  Video = 'video',
  Audio = 'audio',
  Archive = 'archive',
  Document = 'document',
  Code = 'code',
  Other = 'other'
}

const FILE_ICON_LABEL_MAP: Record<string, string> = {};
FILE_ICON_LABEL_MAP[FileType.Folder] = 'DIR';
FILE_ICON_LABEL_MAP[FileType.Markdown] = 'MD';
FILE_ICON_LABEL_MAP[FileType.Image] = 'IMG';
FILE_ICON_LABEL_MAP[FileType.Video] = 'VID';
FILE_ICON_LABEL_MAP[FileType.Audio] = 'AUD';
FILE_ICON_LABEL_MAP[FileType.Archive] = 'ZIP';
FILE_ICON_LABEL_MAP[FileType.Document] = 'DOC';
FILE_ICON_LABEL_MAP[FileType.Code] = '</>';
FILE_ICON_LABEL_MAP[FileType.Other] = 'FILE';

const FILE_ICON_BG_COLOR_MAP: Record<string, string> = {};
FILE_ICON_BG_COLOR_MAP[FileType.Folder] = '#D99000';
FILE_ICON_BG_COLOR_MAP[FileType.Markdown] = '#2F6FDB';
FILE_ICON_BG_COLOR_MAP[FileType.Image] = '#2E8B57';
FILE_ICON_BG_COLOR_MAP[FileType.Video] = '#8E44AD';
FILE_ICON_BG_COLOR_MAP[FileType.Audio] = '#D35400';
FILE_ICON_BG_COLOR_MAP[FileType.Archive] = '#7F8C8D';
FILE_ICON_BG_COLOR_MAP[FileType.Document] = '#3B7DD8';
FILE_ICON_BG_COLOR_MAP[FileType.Code] = '#C0392B';
FILE_ICON_BG_COLOR_MAP[FileType.Other] = '#5F6B7A';

const FILE_DOWNLOAD_COLOR_MAP: Record<string, string> = {};
FILE_DOWNLOAD_COLOR_MAP[FileType.Folder] = '#D99000';
FILE_DOWNLOAD_COLOR_MAP[FileType.Markdown] = '#2F6FDB';
FILE_DOWNLOAD_COLOR_MAP[FileType.Image] = '#2E8B57';
FILE_DOWNLOAD_COLOR_MAP[FileType.Video] = '#8E44AD';
FILE_DOWNLOAD_COLOR_MAP[FileType.Audio] = '#D35400';
FILE_DOWNLOAD_COLOR_MAP[FileType.Archive] = '#606B75';
FILE_DOWNLOAD_COLOR_MAP[FileType.Document] = '#3B7DD8';
FILE_DOWNLOAD_COLOR_MAP[FileType.Code] = '#C0392B';
FILE_DOWNLOAD_COLOR_MAP[FileType.Other] = '#3F7F5F';

const IMAGE_EXTS: Set<string> = new Set(['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'tiff', 'heic']);
const VIDEO_EXTS: Set<string> = new Set(['mp4', 'mov', 'mkv', 'avi', 'wmv', 'flv', 'webm', 'm4v']);
const AUDIO_EXTS: Set<string> = new Set(['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'wma']);
const ARCHIVE_EXTS: Set<string> = new Set(['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz']);
const MARKDOWN_EXTS: Set<string> = new Set(['md', 'markdown']);
const DOCUMENT_EXTS: Set<string> = new Set(['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'rtf']);
const CODE_EXTS: Set<string> = new Set(['js', 'ts', 'ets', 'json', 'html', 'css', 'py', 'java', 'cpp', 'c', 'go', 'rs', 'sh', 'xml', 'yml', 'yaml']);

export function getNameWithoutExtension(name: string): string {
  const dotIndex = name.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex === name.length - 1) return name;
  return name.substring(0, dotIndex);
}

export function getFileExtension(name: string): string {
  const dotIndex = name.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex === name.length - 1) return '';
  return name.substring(dotIndex + 1).toLowerCase();
}

export function getFileType(file: FileInfo): FileType {
  if (file.isDirectory) return FileType.Folder;
  return classifyByExtension(getFileExtension(file.name));
}

export function classifyByExtension(ext: string): FileType {
  if (MARKDOWN_EXTS.has(ext)) return FileType.Markdown;
  if (IMAGE_EXTS.has(ext)) return FileType.Image;
  if (VIDEO_EXTS.has(ext)) return FileType.Video;
  if (AUDIO_EXTS.has(ext)) return FileType.Audio;
  if (ARCHIVE_EXTS.has(ext)) return FileType.Archive;
  if (DOCUMENT_EXTS.has(ext)) return FileType.Document;
  if (CODE_EXTS.has(ext)) return FileType.Code;
  return FileType.Other;
}

export function getFileIconLabel(file: FileInfo): string {
  const t = getFileType(file);
  return FILE_ICON_LABEL_MAP[t] || FILE_ICON_LABEL_MAP[FileType.Other];
}

export function getFileIconBgColor(file: FileInfo): string {
  const t = getFileType(file);
  return FILE_ICON_BG_COLOR_MAP[t] || FILE_ICON_BG_COLOR_MAP[FileType.Other];
}

export function getFileIcon(file: FileInfo): string {
  const t = getFileType(file);
  return FILE_ICON_LABEL_MAP[t] || FILE_ICON_LABEL_MAP[FileType.Other];
}

export function getFileIconColor(file: FileInfo): string {
  const t = getFileType(file);
  return FILE_ICON_BG_COLOR_MAP[t] || FILE_ICON_BG_COLOR_MAP[FileType.Other];
}

export function getDownloadButtonColor(file: FileInfo): string {
  const t = getFileType(file);
  return FILE_DOWNLOAD_COLOR_MAP[t] || FILE_DOWNLOAD_COLOR_MAP[FileType.Other];
}

export function formatFileSize(bytes: number): string {
  if (bytes <= 0) return '0 B';
  const k = 1024;
  const sizes: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

export function formatDate(timestamp: number): string {
  if (timestamp < 0 || isNaN(timestamp)) return '--';
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${year}-${month}-${day} ${hours}:${minutes}`;
}
