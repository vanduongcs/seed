import { createContext, useContext, useEffect, useMemo, useState } from 'react';

const LanguageContext = createContext(null);

const STORAGE_KEY = 'seed-app-language';

export const languages = [
  { code: 'vi', label: 'Việt Nam' },
  { code: 'en', label: 'English' },
];

const phrasePairs = [
  ['Trang chủ', 'Home'],
  ['Lưu trữ', 'Storage'],
  ['Tài khoản', 'Account'],
  ['Khách', 'Guest'],
  ['Chưa đồng bộ', 'Not synced'],
  ['Ngôn ngữ', 'Language'],
  ['Đăng nhập để đồng bộ', 'Log in to sync'],
  ['Đăng ký', 'Sign up'],
  ['Đăng xuất', 'Log out'],
  ['Đăng nhập', 'Log in'],
  ['ĐỊA CHỈ EMAIL', 'EMAIL ADDRESS'],
  ['MẬT KHẨU', 'PASSWORD'],
  ['HỌ VÀ TÊN', 'FULL NAME'],
  ['Nhập mật khẩu', 'Enter password'],
  ['Nhập họ và tên của bạn', 'Enter your full name'],
  ['Tiếp tục không đăng nhập', 'Continue without login'],
  ['Chưa có tài khoản?', 'No account yet?'],
  ['Đăng ký ngay', 'Sign up now'],
  ['Đã có tài khoản?', 'Already have an account?'],
  ['Đăng nhập ngay', 'Log in now'],
  ['Hình ảnh hiển thị', 'Image preview'],
  ['Xem trước ảnh chụp từ camera hoặc tệp ảnh tải lên để phân tích kích thước hạt.', 'Preview a camera capture or uploaded image for grain size analysis.'],
  ['Sẵn sàng', 'Ready'],
  ['Đã xử lý', 'Processed'],
  ['Đánh dấu', 'Overlay'],
  ['Hình dạng', 'Mask'],
  ['Đánh số', 'Labels'],
  ['Ảnh gốc', 'Original'],
  ['Chỉnh hạt nghi ngờ', 'Edit suspect grains'],
  ['Xong chỉnh hạt', 'Finish editing'],
  ['Đang chỉnh kết quả kiểm tra hạt', 'Editing QC result'],
  ['Chưa có ảnh đầu vào', 'No input image'],
  ['Kích thước', 'Size'],
  ['Quyết định', 'Decision'],
  ['Không còn hạt nghi ngờ cần xử lý.', 'No suspect grains need review.'],
  ['Kích thước (mm)', 'Size (mm)'],
  ['Kéo 1 đoạn trên vật mốc', 'Drag one line on the reference marker'],
  ['Xóa vật mốc', 'Clear reference marker'],
  ['Kết nối camera', 'Connect camera'],
  ['Import ảnh', 'Import image'],
  ['Đang xử lý...', 'Processing...'],
  ['Chạy lại', 'Run again'],
  ['Chạy xử lý', 'Run analysis'],
  ['Hướng dẫn căn vật mốc', 'Reference marker guide'],
  ['Quay lại', 'Back'],
  ['Bắt đầu', 'Start'],
  ['Tiếp theo', 'Next'],
  ['QC là gì?', 'What is QC?'],
  ['Đã hiểu', 'Got it'],
  ['Thông số tham chiếu', 'Reference settings'],
  ['Đơn vị đo', 'Measurement unit'],
  ['Milimét (mm)', 'Millimeter (mm)'],
  ['Điểm ảnh (px)', 'Pixels (px)'],
  ['Tỷ lệ thước đo', 'Scale ratio'],
  ['Chưa thiết lập', 'Not set'],
  ['Kết quả phân tích', 'Analysis result'],
  ['Mã lần quét', 'Run ID'],
  ['Tổng số hạt đo được', 'Total measured grains'],
  ['Xuất CSV', 'Export CSV'],
  ['Xuất ảnh kết quả', 'Export result image'],
  ['Số hạt đo được', 'Measured grains'],
  ['Theo lần xử lý hiện tại', 'Current analysis'],
  ['Chưa có dữ liệu', 'No data yet'],
  ['Giá trị trung bình (dài × rộng)', 'Average value (length × width)'],
  ['Thống kê trung bình trên các hạt hợp lệ', 'Average statistics from valid grains'],
  ['Giá trị trung bình diện tích', 'Average area'],
  ['Độ lệch chuẩn (dài × rộng)', 'Standard deviation (length × width)'],
  ['Sau kiểm tra hạt nghi ngờ', 'After suspect-grain QC'],
  ['Dùng SD thô vì hạt nghi ngờ cao', 'Using raw SD because suspect ratio is high'],
  ['Độ lệch chuẩn diện tích', 'Area standard deviation'],
  ['Làm mới', 'Refresh'],
  ['Xóa', 'Delete'],
  ['Chi tiết xử lý', 'Analysis detail'],
  ['Không có overlay', 'No overlay'],
  ['Tên tệp ảnh', 'Image file name'],
  ['Thời gian quét', 'Scan time'],
  ['ĐLC chiều dài (báo cáo)', 'Length SD (reported)'],
  ['ĐLC chiều rộng (báo cáo)', 'Width SD (reported)'],
  ['ĐLC diện tích (báo cáo)', 'Area SD (reported)'],
  ['Hạt nghi ngờ sau kiểm tra', 'Suspect grains after QC'],
  ['Tóm tắt kích thước đã lưu', 'Saved size summary'],
  ['Đóng', 'Close'],
  ['Thông tin người dùng được dùng chung cho web và mobile.', 'User information is shared between web and mobile.'],
  ['Thông tin tài khoản', 'Account information'],
  ['Họ và tên', 'Full name'],
  ['Vai trò', 'Role'],
  ['Đơn vị đo mặc định', 'Default measurement unit'],
  ['Đang lưu...', 'Saving...'],
  ['Lưu thay đổi', 'Save changes'],
  ['Cài đặt', 'Settings'],
  ['Cài đặt website', 'Website settings'],
  ['Chế độ lưu ảnh', 'Image storage mode'],
  ['Lưu ảnh đã xử lý', 'Save processed image'],
  ['Lưu ảnh gốc', 'Save original image'],
  ['Lưu cả hai', 'Save both'],
  ['Tự động lưu kết quả sau xử lý', 'Automatically save results after analysis'],
  ['Hiển thị lưới tham chiếu khi xem ảnh', 'Show reference grid when viewing images'],
  ['Hủy', 'Cancel'],
  ['Lưu cài đặt', 'Save settings'],
  ['Kích thước hạt', 'Grain size'],
  ['Cách đọc kích thước', 'How to read size charts'],
  ['Chiều dài', 'Length'],
  ['Chiều rộng', 'Width'],
  ['Diện tích', 'Area'],
  ['Tất cả', 'All'],
  ['Độ đồng đều', 'Uniformity'],
  ['Biểu đồ phân bố', 'Distribution chart'],
  ['Cách đọc phần kích thước', 'How to read size charts'],
  ['Hạt cần xem lại', 'Grains to review'],
];

const viToEn = new Map(phrasePairs);
const enToVi = new Map(phrasePairs.map(([vi, en]) => [en, vi]));

function translateTextValue(value, language) {
  const map = language === 'en' ? viToEn : enToVi;
  const trimmed = value.trim();
  if (!trimmed || !map.has(trimmed)) return value;
  return value.replace(trimmed, map.get(trimmed));
}

function translateDom(root, language) {
  if (typeof document === 'undefined') return;
  const walker = document.createTreeWalker(
    root,
    NodeFilter.SHOW_TEXT,
    {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || ['SCRIPT', 'STYLE', 'TEXTAREA', 'INPUT'].includes(parent.tagName)) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    }
  );

  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    const nextValue = translateTextValue(node.nodeValue, language);
    if (nextValue !== node.nodeValue) node.nodeValue = nextValue;
  }

  for (const element of root.querySelectorAll?.('[aria-label], [title], [placeholder], [alt]') ?? []) {
    for (const attr of ['aria-label', 'title', 'placeholder', 'alt']) {
      if (element.hasAttribute(attr)) {
        const currentValue = element.getAttribute(attr);
        const nextValue = translateTextValue(currentValue, language);
        if (nextValue !== currentValue) element.setAttribute(attr, nextValue);
      }
    }
  }
}

export function LanguageProvider({ children }) {
  const [language, setLanguageState] = useState(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    return saved === 'en' ? 'en' : 'vi';
  });

  const setLanguage = (nextLanguage) => {
    const code = nextLanguage === 'en' ? 'en' : 'vi';
    setLanguageState(code);
    localStorage.setItem(STORAGE_KEY, code);
  };

  useEffect(() => {
    document.documentElement.lang = language === 'en' ? 'en' : 'vi';
    translateDom(document.body, language);
    const observer = new MutationObserver(() => translateDom(document.body, language));
    observer.observe(document.body, { childList: true, subtree: true, characterData: true });
    return () => observer.disconnect();
  }, [language]);

  const value = useMemo(
    () => ({
      language,
      setLanguage,
      text: (vi, en) => (language === 'en' ? en : vi),
    }),
    [language]
  );

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const value = useContext(LanguageContext);
  if (!value) {
    throw new Error('useLanguage must be used inside LanguageProvider');
  }
  return value;
}
