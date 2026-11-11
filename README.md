# Quản lý cửa hàng — Flutter desktop

Ứng dụng tiếng Việt cho danh mục sản phẩm, từng chiếc xe và phụ tùng. Dùng MongoDB cục bộ, không cần Internet khi vận hành. Có đọc danh mục và lô hàng từ MongoDB, cùng biểu mẫu nhập hàng dạng bản nháp. Chưa ghi phiếu nhập, thêm/sửa/xóa dữ liệu kho, bán hàng hoặc thu tiền.

## Chạy trên Mac

Yêu cầu Flutter 3.44 / Dart 3.12, Xcode và MongoDB cục bộ đang chạy. Bộ gói Flutter cần tải lần đầu khi phát triển; giao diện không tải font, ảnh hoặc dữ liệu từ Internet.

```sh
flutter pub get
flutter run -d macos
```

Kết nối mặc định: `mongodb://127.0.0.1:27017/XM`. Ứng dụng kiểm tra marker `product_schema_v2` để tránh đọc nhầm cấu trúc cũ. Có thể đổi cấu hình khi chạy/build:

```sh
flutter run -d macos --dart-define=MONGO_URI=mongodb://127.0.0.1:27017/XM
```

Không lưu mật khẩu vào mã nguồn. Bản đầu dành cho một máy cục bộ, chưa có đăng nhập hoặc cơ chế triển khai cho nhiều máy.

## Màn hình chính hiện tại

Dashboard giữ style desktop ban đầu: thanh bên, nền sáng và ô bo góc trắng. Đã bỏ thanh Không gian làm việc và tiêu đề trang; tab nằm ở đầu vùng nội dung. Các mục được gom theo nhóm; bấm vào nhóm ở thanh bên hoặc ô tổng quan để xem tab con:

- Sản phẩm: Xe mới, Xe cũ, Phụ tùng. Mỗi tab có ô tìm kiếm và nút + mở khung nhập tương ứng (nhập xe mới / mua xe cũ / nhập phụ tùng), không có tab nhập riêng.
- Khách hàng: Khách hàng.
- Bán hàng: Bán hàng.
- Công nợ: Công nợ bán hàng, Công nợ nhập hàng, Nợ cũ.
- Cầm đồ: Cầm đồ.
- Tài chính: Thu chi, Vay vốn.
- Báo cáo: Báo cáo.
- Danh mục: Hãng xe, Xã / địa chỉ.

Chuyển nhóm/tab đã hoạt động, nhớ tab vừa chọn khi quay lại nhóm. Các nhóm khác hiện chỉ có tên. Nhóm Sản phẩm đã có thanh tìm kiếm và nút +; nút + mở view có tab Nhập lẻ trước và tab Lô hàng sau. Có biểu mẫu, thêm/xóa dòng, tính tổng và xem trước phiếu; chưa có truy vấn tìm kiếm hay ghi dữ liệu nhập vào MongoDB. Mở dashboard không cần kết nối MongoDB. Cửa sổ hẹp dùng menu bên, tab dài có thể cuộn ngang.

Màn hình kho và các chức năng đọc dữ liệu bên dưới vẫn được giữ trong mã nguồn để nối vào từng mục sau.

## Chức năng kho đã có trong mã nguồn

- Danh mục sản phẩm, danh sách xe, danh mục phụ tùng.
- Số lượng thực đọc từ MongoDB, không dùng số mẫu trên giao diện.
- Tìm tên/mã, phân trang 30 dòng, lọc xe mới/cũ/chưa phân loại.
- Chi tiết xe nối với `XeMoi`, `XeCu` để xem số khung, số máy, biển số.
- Chi tiết sản phẩm cho biết số chiếc liên kết; phụ tùng không có dòng tồn được hiển thị chưa ghi nhận, không tự coi là 0.
- Thông báo và nút thử lại khi chưa kết nối được dữ liệu.
- Giao diện desktop, hỗ trợ cửa sổ hẹp bằng menu bên và bảng cuộn ngang.

Các số lượng xe là tổng dữ liệu lịch sử, không phải số xe đang tồn. Giá bán đã ghi là dữ liệu nguồn, không phải bảng giá mới.

## Cấu trúc MVC

```text
lib/
  main.dart                         # Khởi động ứng dụng
  app.dart                          # Cấu hình ứng dụng, mở dashboard
  models/
    goods_receipt/goods_receipt_models.dart # Loại nhập, dòng hàng, phiếu xem trước
    dashboard/dashboard_module.dart # Các chức năng con
    dashboard/dashboard_group.dart  # Nhóm chức năng và danh sách tab
    inventory/inventory_models.dart # Loại danh mục, dữ liệu phân trang, thống kê
    repositories/inventory_repository.dart # Hợp đồng truy xuất dữ liệu
  controllers/
    goods_receipt_controller.dart   # Bản nháp lô/lẻ, kiểm tra và tính tổng
    dashboard_controller.dart       # Chọn nhóm/tab, nhớ tab trong từng nhóm
    inventory_controller.dart       # Trạng thái, tìm kiếm, lọc, phân trang, xử lý lỗi
  views/
    dashboard/dashboard_screen.dart # Các nhóm và tab chức năng
    products/product_tab.dart       # Ô tìm kiếm, nút + mở view nhập
    goods_receipt/goods_receipt_screen.dart # Biểu mẫu nhập lô/lẻ và xem phiếu
    inventory/inventory_screen.dart  # Hiển thị, tương tác và hộp thoại chi tiết
  services/
    mongo_inventory_repository.dart # Hiện thực truy vấn MongoDB chỉ đọc
  core/
    config/database_config.dart     # Cấu hình kết nối
    formatters/inventory_formatters.dart # Định dạng số, tiền và nhãn tiếng Việt
    theme/app_theme.dart            # Giao diện nền
```

Luồng: View nhận thao tác → Controller xử lý → repository/service đọc dữ liệu → Model trả kết quả → Controller thông báo View dựng lại qua `ListenableBuilder`. Model và hợp đồng repository không phụ thuộc widget/MongoDB. View không truy vấn MongoDB hoặc tự quản lý trạng thái tải dữ liệu. Controller không giữ TextEditingController, BuildContext hay widget.

Dashboard có Controller riêng để chuyển nhóm/tab; chưa kết nối cơ sở dữ liệu. Màn hình kho nhận `InventoryController` từ nơi mở màn hình; nơi đó phải khởi tạo, tải và đóng Controller theo vòng đời. Controller sở hữu timer tìm kiếm và trạng thái yêu cầu, hủy timer khi đóng, bỏ qua phản hồi cũ và đóng repository. Khi thêm phân hệ mới, thêm Model, Controller và View tương ứng theo ba thư mục trên.

`test/` có kiểm thử Controller và giao diện; `test/support/` chứa repository giả dùng riêng cho kiểm thử. `tool/check_database.dart` kiểm tra kết nối thật, phân trang và liên kết chỉ đọc.

## Kiểm tra và build

```sh
flutter analyze
flutter test
dart run tool/check_database.dart
flutter build macos --debug
```

Bấm đúp `tool/release.command` trong Finder. File này tăng số build thêm 1 (ví dụ `1.0.0+1` thành `1.0.0+2`), commit rồi đẩy nhánh `main`. Cửa sổ Terminal ở lại đến khi nhấn Enter.

GitHub Actions dựng công cụ sao chép SQL cho Windows, đóng bộ cài và đăng bản phát hành. Ứng dụng so số build này với `latest.json`, rồi tải file cài từ bản phát hành mới nhất:

`https://github.com/hoicauviet-svg/xemay-app/releases/latest`

Trên máy Windows có Flutter, Python 3.12 và Inno Setup 6, có thể đóng tại chỗ:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_windows_installer.ps1
```

Bản macOS yêu cầu macOS 12 trở lên. Không hỗ trợ Flutter Web do bản đầu kết nối MongoDB cục bộ qua thư viện desktop.

Sau khi build, ứng dụng nằm ở `build/macos/Build/Products/Debug/Quan Ly Cua Hang.app`.

## Tiếp theo

Thêm/sửa danh mục, nhập phụ tùng và từng chiếc xe; sau đó đến hóa đơn mua/bán nhiều dòng. Chỉ triển khai thao tác tiền và tồn nhiều collection sau khi có cơ chế giao dịch và kiểm tra liên kết phù hợp. Không dùng ứng dụng hiện tại để ghi dữ liệu trực tiếp.

## View nhập hàng

Mở bằng nút + trong Xe mới, Xe cũ hoặc Phụ tùng. View bố trí hai tab Nhập lẻ / Lô hàng ở trên cùng, cố định khi cuộn biểu mẫu; topbar dùng chung nằm phía trên với nút quay lại ở mép trái cửa sổ và tiêu đề theo loại hàng. Nhập lẻ là một dòng hàng; với phụ tùng có thể nhập nhiều đơn vị cùng mã hàng. Nhập lô cho phép thêm/xóa nhiều dòng. Mỗi chiếc xe là một dòng có số lượng 1, có trường số khung, số máy và biển số; phụ tùng dùng tên, số lượng nguyên dương và giá nhập. Số tiền nhập theo đồng nguyên, không dùng double để tính tổng.

Hai chế độ giữ bản nháp riêng khi chuyển qua lại trong màn hình. Thông tin phiếu gồm ngày nhập, đối tác/nhà cung cấp, số chứng từ, ghi chú. Nút Xem phiếu nhập kiểm tra dữ liệu và hiển thị xem trước; không tạo chứng từ hay ghi tồn/công nợ vào MongoDB. Quay lại màn hình sản phẩm sẽ đóng bản nháp hiện tại.

### Nhập lô theo hai bước

Đã đối chiếu trực tiếp collection `NhapHang` trong MongoDB: `IdNhapHang`, `SoLuong`, `SoTien`, `NguoiCho`, `NoiNhap`, `NgayNhap`, `SoTienDaTra`, `SoTienConNo`. Biểu mẫu hiển thị đủ thông tin tương ứng; mã lô để tự cấp khi có chức năng lưu. Còn nợ được tính bằng tổng tiền lô trừ đã trả; không cho đã trả lớn hơn tổng tiền.

Bước 1 chỉ hiển thị thông tin lô. Bấm Tiếp tục để kiểm tra và xác nhận bản nháp. Bước 2 mới hiển thị form thêm sản phẩm và tóm tắt lô, có thể quay lại sửa mà không mất các dòng đã nhập. Tổng tiền lô khai báo được giữ riêng với tổng giá của các sản phẩm; chưa tự sửa số tiền lô theo danh sách sản phẩm. Không cho kê số lượng sản phẩm vượt số lượng khai báo.

Luồng này hiện vẫn là bản nháp và xem trước, chưa tạo `IdNhapHang`, chưa ghi lô, sản phẩm, thanh toán hoặc công nợ vào MongoDB. `BatchReceiptInfo.toDatabaseFields()` cung cấp ánh xạ đầy đủ các trường nghiệp vụ cho bước nối lưu dữ liệu sau.

## Topbar dùng chung

`lib/views/widgets/app_top_bar.dart` cung cấp `AppTopBar`. Gắn vào `Scaffold.appBar` để nút quay lại nằm ở mép trái cửa sổ, không bị thụt vào vùng biểu mẫu giới hạn chiều rộng. Bắt buộc truyền `title`; có thể truyền `onBack`, `actions`, `bottom` hoặc ẩn nút quay lại bằng `showBackButton: false`. Mặc định nút quay lại dùng Navigator.maybePop.

```dart
Scaffold(
  appBar: AppTopBar(title: 'Nhập hàng'),
  body: ...,
)
```

View nhập hàng đang dùng topbar này với tiêu đề tương ứng Nhập xe mới, Mua xe cũ hoặc Nhập phụ tùng. Các tab Nhập lẻ / Lô hàng cố định ngay bên dưới.

## Lô hàng và danh sách sản phẩm

View `goods_receipt_screen.dart` hiện có tab Nhập lẻ ở đầu (mặc định) và tab Lô hàng. Tab Lô hàng tải dữ liệu khi mở lần đầu; có tìm mã lô/vận chuyển/đối tác, phân trang, làm mới và nút Nhập lô hàng. Nút này mở popup dùng chung `FormPopup`, chứa `goods_receipt_form_screen.dart` ở chế độ lô, vẫn giữ quy trình thông tin lô → thêm sản phẩm → xem trước. Biểu mẫu mới chưa lưu vào MongoDB, nên chưa tạo dòng lô mới trong danh sách.

Bấm một dòng lô mở `batch_details_screen.dart`: thông tin lô và các sản phẩm liên kết. Nguồn dữ liệu hiện có 1.680 lô `NhapHang`; các lô cũ thuộc luồng xe mới, liên kết bằng `XeMoi.IdNhapHang → Xe.IdXe → SanPham.IdSanPham`. Không nối bản ghi theo mã trùng ngẫu nhiên. Tab trong ngữ cảnh xe cũ/phụ tùng chỉ lấy lô có loại được xác định tương ứng; dữ liệu nguồn chưa có các lô này.

Số lượng khai báo và số sản phẩm thực tìm thấy được hiển thị riêng, không tự sửa số tiền/số lượng lịch sử. Các trường tiền ở màn xem phản ánh giá trị đang lưu trong database, kể cả dữ liệu bất thường đã ghi nhận trước đây. Toàn bộ chức năng danh sách và chi tiết chỉ đọc.

MVC: `models/batches`, `models/repositories/batch_repository.dart`, `controllers/batch_list_controller.dart`, `controllers/batch_details_controller.dart`, `services/mongo_batch_repository.dart`, `views/batches`. `tool/check_batches.dart` đối chiếu số lô, phân trang và liên kết với nguồn thật bằng truy vấn chỉ đọc.

## Chi tiết lô hàng dạng tab

Chi tiết lô gồm bốn tab: Thông tin (mặc định), Danh sách sản phẩm, Lịch sử thanh toán, Thanh toán. Thông tin lô được đọc lại từ `NhapHang` khi mở/làm mới. Lịch sử lấy toàn bộ dòng `TraNoNhapHang` đúng `IdNhapHang`, gồm mã lần trả, ngày, số tiền trả, số còn nợ sau lần trả và ghi chú; giữ cả các dòng số tiền 0 của lịch sử, không tính lại hoặc thay thế số dư trong `NhapHang` bằng tổng lịch sử.

Tab Thanh toán có số tiền, ngày, ghi chú và nút Xem phiếu thanh toán. Kiểm tra số tiền dương, không vượt dư nợ đang hiển thị; lỗi tải dữ liệu sẽ chặn xem trước. Chưa ghi khoản thanh toán, chưa thay đổi dư nợ hay lịch sử trong database. Số tiền và số dư trong dữ liệu cũ vẫn giữ kiểu nguồn; không dùng phép tính tổng mới để tự sửa các chênh lệch lịch sử.

### Bảng sản phẩm trong lô và nút thêm

Hàng tiêu đề bảng sản phẩm được cố định khi cuộn dọc. Tiêu đề và dữ liệu dùng cùng chiều rộng cột và cùng vùng cuộn ngang để không lệch cột. Chỉ bảng sản phẩm bật chế độ này; các bảng khác giữ cách hiển thị hiện tại.

Nút trên topbar chi tiết lô đã đổi từ làm mới sang + Thêm sản phẩm vào lô. Nút mở biểu mẫu sản phẩm gắn với mã lô đang xem, không mở form tạo lô khác hoặc yêu cầu nhập lại thông tin lô. Bản xem trước mang `batchId` của lô hiện tại. Chưa ghi sản phẩm, tồn kho hoặc công nợ vào database; quay về màn chi tiết sẽ đọc lại dữ liệu hiện có.

### Popup thêm sản phẩm vào lô

Đã bỏ nút thêm trên topbar. Danh sách sản phẩm kéo xuống sát đáy vùng nội dung, không chừa dải trống bên dưới; FAB + nổi đè lên danh sách ở góc dưới bên phải khi đang mở tab Danh sách sản phẩm và tải dữ liệu thành công; các tab khác không hiển thị FAB. Bấm FAB mở popup có tiêu đề mã lô và nút đóng, dùng lại form sản phẩm trong chế độ embedded. Popup có chiều cao theo cửa sổ, phần form cuộn riêng; Hủy hoặc Đóng quay về đúng tab đang xem. Luồng vẫn là bản nháp/xem trước, chưa ghi sản phẩm vào database.

Popup Nhập lô hàng dùng cùng khung `views/widgets/form_popup.dart` với popup thêm sản phẩm: tiêu đề, nút Đóng, phần form cuộn và nút thao tác phía dưới. Luồng nhập thông tin lô trước rồi mới thêm sản phẩm giữ nguyên; đóng hoặc hủy quay về tab Lô hàng đang mở.

Nhãn giao diện lô hàng đã đổi: `NguoiCho` hiển thị Vận chuyển; `NoiNhap` hiển thị Đối tác / nhà cung cấp. Áp dụng cho form, thông tin lô, danh sách, tìm kiếm, xem trước và thông báo kiểm tra. Chỉ đổi nhãn, không đổi các trường hoặc giá trị đã lưu trong MongoDB.

## Danh mục đối tác và vận chuyển

Đã tách `DoiTac` và `VanChuyen` trong MongoDB, liên kết lô cũ bằng `IdDoiTac`/`IdVanChuyen`; tên nguồn và số tiền giữ nguyên. Có 239 đối tác và 81 vận chuyển được tạo từ tên nguồn, chưa có các chi tiết liên hệ nên để trống.

Form nhập lô: hai trường Đối tác / nhà cung cấp và Vận chuyển dùng autocomplete, có nút + mở popup thêm. Đối tác có tên, điện thoại, địa chỉ, mã số thuế, người đại diện và ghi chú; vận chuyển có tên, điện thoại, biển số xe và ghi chú. Lưu và chọn thực sự lưu danh mục vào MongoDB và tự chọn bản ghi mới. Sửa chữ sau khi chọn sẽ bỏ ID cũ, cần chọn lại trước khi Tiếp tục. Nhập lẻ cũng dùng autocomplete đối tác.

MVC bổ sung: `models/directory`, `models/repositories/directory_repository.dart`, `controllers/directory_controller.dart`, `services/mongo_directory_repository.dart`, `views/directory`. `tool/check_directories.dart` đọc số lượng nguồn thật, thử lưu/đọc đầy đủ các trường trong database thử riêng rồi xóa database thử. Không tạo danh mục mẫu trong XM khi kiểm thử.

Chi tiết chuyển dữ liệu ở `../CAU_TRUC_DOI_TAC_VAN_CHUYEN.md`. Chức năng lưu phiếu nhập và ghi sản phẩm/tiền vẫn chưa nối; thao tác lưu danh mục hoạt động độc lập.

Popup đối tác và vận chuyển dùng cùng `FormSection`/`ResponsiveFormFields` với view nhập hàng: nền xám nhạt, khối trắng bo góc và viền mảnh, trường thông tin hai cột trên cửa sổ rộng/một cột khi hẹp, ghi chú riêng. Hàng Hủy / Lưu và chọn cố định phía dưới, phần nội dung cuộn độc lập. Cơ chế lưu dữ liệu và tự chọn giữ nguyên.

## Danh sách sản phẩm trên dashboard

Ba tab Xe mới, Xe cũ, Phụ tùng đọc trực tiếp MongoDB qua `ProductListController`. Xe lọc theo `TinhTrangXe` và ghép thông tin số khung, số máy, biển số; phụ tùng ghép số lượng từ `TonKhoPhuTung`, thiếu số lượng hiển thị Chưa ghi nhận. Danh sách gồm toàn bộ bản ghi theo loại, chưa lọc tồn/bán theo trường trạng thái cũ.

Tìm theo tên, mã số xe/sản phẩm, số khung, số máy hoặc biển số; phân trang 30 dòng, tiêu đề bảng cố định, giữ ô tìm kiếm và nút + cao 48. Trở về từ nhập hàng sẽ tải lại danh sách. Dữ liệu kiểm tra: 13.526 xe mới, 1.921 xe cũ, chưa có phụ tùng; 45 xe chưa xác định loại không tự xếp vào hai tab xe.

### Lọc bán/tồn và giỏ hàng

Danh sách mặc định lọc Chưa bán / còn hàng; biểu tượng lọc ở cuối ô tìm kiếm cho phép xem Đã bán / hết hàng hoặc Tất cả. Đã đối chiếu toàn bộ 15.209 ID xe trong ChiTietHoaDonBan khớp chính xác Xe.TinhTrang=false; true là chưa bán. Mỗi xe hiển thị tồn 1/0; phụ tùng dùng số lượng thực trong TonKhoPhuTung, chưa có số liệu không được coi là còn hàng. Kiểm tra hiện có 221 xe mới và 19 xe cũ chưa bán, còn 43 xe chưa xác định loại vẫn không tự xếp vào hai tab.

Nút giỏ ở cuối dòng thêm sản phẩm còn hàng; xe chỉ thêm một lần, phụ tùng tăng số lượng tối đa bằng tồn đã tải. Giỏ dùng chung giữa các tab trong phiên chạy ứng dụng; nút giỏ trên thanh công cụ mở danh sách và cho bỏ từng sản phẩm. Chưa có thanh toán/lưu đơn, chưa trừ hoặc giữ tồn trong MongoDB.

Giỏ hàng được đưa ra dashboard: nút Giỏ hàng ở cuối thanh điều hướng trên cửa sổ rộng, hoặc biểu tượng trên thanh đầu trang ở cửa sổ hẹp. Nút hiển thị số lượng và mở giỏ dùng chung kể cả khi đang ở Tổng quan/nhóm khác. Toolbar sản phẩm chỉ giữ tìm kiếm, bộ lọc và nút nhập; biểu tượng giỏ ở cuối từng dòng vẫn thêm sản phẩm vào giỏ.

## Tab khách hàng

Đọc collection `KhachHang`, ghép tên xã từ `Xa`; bảng có mã, tên khách hàng, điện thoại, địa chỉ và nút xóa. Tìm theo mã, tên, điện thoại, địa chỉ chi tiết/tên xã; lọc có/chưa có số điện thoại. Phân trang 30 dòng, bảng vừa ngang với tiêu đề cố định; cửa sổ hẹp dùng danh sách gọn.

Nút thêm mở popup cùng style form nhập hàng: tên bắt buộc, điện thoại và một ô địa chỉ chi tiết nhập cả thôn, số nhà, xã. Không có ô chọn xã riêng. Lưu thực sự vào MongoDB, dùng bộ đếm tăng nguyên tử `_app_counters/KhachHang`, khởi tạo theo IdKH lớn nhất để không trùng mã cũ. Xóa có xác nhận, chặn nếu được tham chiếu bởi HoaDonBan.IdKH, HoaDonMua.IdKh, CamDo.IdKhachHang hoặc NoCu.IdKH. Khách hàng được xóa khỏi danh sách bằng DaXoa=true và NgayXoa; giữ bản ghi để có thể khôi phục, không dùng lại mã.

MVC: `models/customers`, `models/repositories/customer_repository.dart`, `services/mongo_customer_repository.dart`, `controllers/customer_controller.dart`, `views/customers`. `tool/check_customers.dart` đọc dữ liệu thật nhưng chỉ thử thêm/xóa trong database thử riêng rồi dọn database đó. Không tạo hoặc xóa khách hàng thực trong XM khi kiểm thử.

Địa chỉ khách hàng cũ vẫn ghép tên xã từ IdXa khi hiển thị để giữ đầy đủ thông tin; khách hàng thêm mới lưu nguyên địa chỉ đã nhập trong DiaChiChiTiet. Đã bỏ bộ lọc xã.

### Chi tiết khách hàng và đơn hàng

Bấm một dòng khách hàng (hoặc tên/thông tin trên danh sách hẹp) mở màn hình dùng AppTopBar có nút quay lại. Hai tab Thông tin / Đơn hàng hiển thị thông tin mới nhất và địa chỉ đầy đủ. Nút xóa trên dòng vẫn hoạt động độc lập.

Đơn hàng khách hàng chỉ là HoaDonBan lọc chính xác IdKH. Phiếu mua xe từ người bán được chuyển sang mục Đối tác / nhà cung cấp và tra theo HoaDonMua.IdDoiTac. Có phân trang 30 đơn, ngày, sản phẩm, số lượng, tổng tiền và ghi chú; ghép chi tiết qua IdHoaDon/IdMua rồi tên SanPham. Tổng tiền chỉ tính khi tất cả dòng có DonGia và SoLuong thực; thiếu giá hiển thị Chưa ghi nhận, không lấy DonGiaNguon hoặc giá hiện tại của xe để suy ra giá bán lịch sử. Chưa có thao tác chỉnh sửa đơn trên màn hình này.


## Đối tác / nhà cung cấp và người bán xe

Dashboard có mục Đối tác / nhà cung cấp với danh sách phân trang 30 dòng, tìm kiếm, thêm mới dùng popup danh mục hiện có. Bấm đối tác mở Thông tin / Phiếu mua; thông tin gồm tên, điện thoại, địa chỉ, mã số thuế, người đại diện, ghi chú. Phiếu mua đọc HoaDonMua theo IdDoiTac và ChiTietHoaDonMua theo IdMua; giữ nguyên nguyên tắc không lấy giá nguồn chưa đối soát để suy ra tổng tiền.

Đã chuyển 1.899 người bán xe từ HoaDonMua.IdKh sang DoiTac, tạo 1.899 đối tác mới, liên kết 1.922 phiếu mua. Tổng danh mục có 2.138 đối tác. Từng người bán được nhận diện theo IdKH gốc, không tự gộp người trùng tên với nhau hoặc với nhà cung cấp cũ. Địa chỉ đối tác được ghép thôn/số nhà và tên xã; chi tiết liên hệ nguồn được giữ lại.

KhachHang gốc không xóa vật lý: thêm IdDoiTac và AnKhoiDanhSachKhachHang=true cho người chỉ bán xe; danh sách khách hàng còn 18.147 bản ghi hiển thị. Khi nguồn có người vừa bán xe vừa là khách mua/cầm đồ/công nợ, quy trình vẫn giữ họ hiển thị ở Khách hàng. HoaDonMua.IdKh gốc giữ làm dấu vết lịch sử, giao diện phiếu mua mới dùng IdDoiTac. Các ngày, tiền, xe và chi tiết hóa đơn không thay đổi.

Quy trình `../move_sellers_to_partners.py` mặc định chỉ phân tích, `--apply` tự sao lưu trước khi cập nhật; thử quy trình qua `../test_move_sellers_to_partners.py` bằng database riêng. Bản sao lưu lần chuyển thực tế: `../seller-partner-backup-20261101-154459/XM-before-sellers.archive.gz`; báo cáo và mã kiểm tra file nằm cùng thư mục. Metadata seller_partners_v1 ghi thông tin chuyển đổi. `tool/check_partners.dart` xác nhận toàn bộ liên kết thật và thử tra cứu phiếu mua trong database riêng, sau đó dọn database thử.

Dashboard đã bỏ nhóm Bán hàng cũ (màn hình trống). Nút Giỏ hàng dùng chung đổi nhãn thành Bán hàng và mở tab Bán hàng trong dashboard; nút giỏ cuối dòng sản phẩm có nhãn Thêm vào đơn bán hàng. Danh sách sản phẩm đã chọn, số lượng và thao tác bỏ khỏi đơn tiếp tục dùng chung giữa các tab.

Bán hàng mở trong vùng nội dung dashboard dưới dạng tab, không dùng popup. Chuyển sang nhóm khác rồi trở lại vẫn giữ các sản phẩm đã chọn; nút Bán hàng ở thanh điều hướng hoặc thanh đầu cửa sổ hẹp cùng mở tab này.

## Dịch vụ

Tab Dịch vụ trong Sản phẩm có ô tìm kiếm theo tên/mô tả và nút + mở popup thêm. Ô tìm kiếm và nút cùng cao 48 px. Form chỉ có Tên dịch vụ (bắt buộc), Mô tả (tùy chọn) và Giá tiền (số nguyên từ 0 đồng); lưu thực sự vào collection DichVu với TenDichVu, MoTa, GiaTien và _id kỹ thuật. Không quản lý tồn kho cho dịch vụ.

Danh sách có ba cột tên, mô tả, giá; bảng vừa ngang, tiêu đề cố định, cửa sổ hẹp dùng danh sách gọn. Có phân trang 30 dòng, trạng thái tải/lỗi và thử lại. Thêm mới thành công tải lại danh sách, giữ từ khóa tìm kiếm hiện tại. MVC bổ sung models/services, models/repositories/service_repository.dart, controllers/service_controller.dart, services/mongo_service_repository.dart, views/products/service_tab.dart và service_editor_popup.dart. tool/check_services.dart chỉ đọc database thật và thử ghi/tìm kiếm/phân trang trong database riêng rồi dọn database thử.


## Thiết kế view bán hàng

Tab Bán hàng có hai vùng trên cửa sổ rộng: danh sách sản phẩm/dịch vụ ở trái; khách hàng, ngày bán, ghi chú và thanh toán ở phải. Cửa sổ hẹp xếp dọc và cuộn toàn bộ. Các khối dùng cùng nền, viền, bo góc và màu xanh của ứng dụng.

Chọn sản phẩm hoặc dịch vụ từ tab tương ứng rồi quay lại Bán hàng. Dịch vụ có nút thêm vào đơn, lấy giá danh mục; phụ tùng lấy giá tham khảo nếu có. Xe luôn yêu cầu nhập giá bán trên đơn, không dùng giá nguồn lịch sử. Mỗi xe một chiếc; số lượng phụ tùng không vượt tồn đã tải; dịch vụ có thể tăng số lượng. Các dòng có giá, thành tiền và nút bỏ khỏi đơn.

Khách hàng tìm theo tên/mã/điện thoại, chọn một bản ghi thực hoặc thêm ngay bằng nút +; khách hàng mới được lưu rồi tự chọn vào đơn. Chữ nhập chưa được chọn không được coi là khách hàng đã xác định. Có giảm giá theo số tiền, khách thanh toán, còn phải thu và tiền thừa. Giá và các khoản tiền phải là số nguyên không âm; giảm giá không vượt tiền hàng. SalesController thuộc dashboard nên thông tin đơn và giá nhập vẫn giữ khi chuyển nhóm/tab.

Nút Xem trước đơn hàng kiểm tra dữ liệu và hiển thị tổng hợp bản nháp. Chưa có ghi hóa đơn, thu tiền, giữ/trừ tồn hoặc in chứng từ. Màn hình và phép tính được kiểm thử độc lập, các lần kiểm tra không tạo hóa đơn thật trong XM.

Bố cục bán hàng đã thu gọn: thông tin khách hàng và đơn hàng ở trên (hai khối cạnh nhau trên cửa sổ rộng), danh sách hàng ở giữa, thanh toán ở dưới cùng. Trên cửa sổ rộng/cao đủ, danh sách cuộn riêng trong khi thông tin và thanh toán đứng yên; cửa sổ nhỏ xếp dọc và cuộn trang. Dòng hàng hiển thị gọn theo hàng ngang khi đủ chỗ. Hai nút thêm được gộp thành một nút + ở đầu danh sách; bấm để chọn Thêm sản phẩm hoặc Thêm dịch vụ và chuyển đến tab tương ứng. Các phép tính và bản nháp giữ nguyên.


### Đối chiếu các trường bán hàng với database

Giao diện đã bỏ chữ/nút Khách lẻ, bỏ phương thức thanh toán và nút reset. Nút + khách hàng mở lại form ba trường tên/điện thoại/địa chỉ; repository trả về chính bản ghi vừa lưu có IdKH để tự chọn, không tra lại theo tên hoặc đoán mã. Nút + thêm hàng chuyển lên góc phải tiêu đề danh sách, thay vị trí reset; không còn FAB.

Đã kiểm tra schema nguồn và validator thực tế ngày 04/11/2026:

- HoaDonBan: IdHoaDon tự cấp, IdKH là mã khách được chọn (nguồn cho phép null), NgayMua là ngày bán, GhiChu là ghi chú. NgayHen và NgayTinhLai dùng cho ngày hẹn thanh toán/ngày tính lãi. Form mới bắt buộc chọn cả hai khi đơn còn nợ; chứng từ lịch sử giữ nguyên. IdXe/IdSanPham ở header cũ là liên kết đơn một xe; đơn nhiều hàng cần lấy từ chi tiết.
- ChiTietHoaDonBan: IdHoaDon liên kết đầu đơn, IdSanPham, IdXe (xe mới/cũ), LoaiSanPham, SoLuong, DonGia. Validator hiện chỉ chấp nhận xe/phu_tung, không chấp nhận dịch vụ. Để lưu dịch vụ phải bổ sung loại dich_vu và IdDichVu chuỗi, cho phép IdSanPham null ở đúng nhánh dịch vụ. Không dùng mã dịch vụ thay IdSanPham hoặc gán mã giả.
- Tiền hàng/giảm giá/tổng thanh toán chưa có trường tương ứng ở header hiện tại. Cần bổ sung các trường tổng tiền minh bạch khi nối lưu; giá lịch sử DonGiaNguon chưa đối soát không được ghi đè vào DonGia của đơn mới.
- SoNo: IdHoaDon, SoTienDaTra là số tiền thực thu tối đa bằng tổng thanh toán; SoTienConNo là phần còn phải thu. Tiền khách đưa lớn hơn tổng đơn phải tách tiền thừa; không ghi cả tiền thừa vào số đã trả.
- TraNo: liên kết bằng IdSoNo; trường nguồn viết chính xác SotienTra (không phải SoTienTra), ngày thu NgayTra, dư nợ SoCoNo. Mã LoaiTraNo và các trường lãi cần hiểu đúng nghiệp vụ trước khi ghi, không đoán mã.
- Ngày nguồn lưu theo thành phần giờ lịch SQL, không chuyển múi giờ; MongoDB hiện chạy standalone, nên khi nối lưu hóa đơn/chi tiết/thu tiền/tồn kho phải có phương án bảo đảm không ghi dở dang.

Lần cập nhật này chỉ đọc/đối chiếu cấu trúc bán hàng và cập nhật giao diện; không thay validator, không ghi hóa đơn hoặc thay tồn kho. Chức năng thêm khách hàng lưu thật; kiểm thử ghi khách hàng chạy trong database riêng.


## Lưu đơn bán hàng — sales_schema_v3

Đã cập nhật XM hỗ trợ xe, phụ tùng và dịch vụ trong ChiTietHoaDonBan. Mỗi loại có đúng khóa liên kết: xe dùng IdXe/IdSanPham; phụ tùng dùng IdSanPham; dịch vụ dùng IdDichVu chuỗi và không giả lập IdSanPham. Các dòng mới lưu tên chụp tại lúc bán, số lượng, đơn giá thực nhập và thành tiền. Header bổ sung TongTienHang, GiamGia, TongThanhToan, SoTienKhachDua, SoTienDaTra, SoTienConNo, TienThua; validator kiểm tra tổng thanh toán bằng tiền hàng trừ giảm giá và các khoản tiền khớp nhau. Giá lịch sử chưa đối soát không thay đổi.

Nút Lưu đơn hàng ghi HoaDonBan, ChiTietHoaDonBan, SoNo và TraNo; SoTienDaTra/SotienTra chỉ là thực thu, tối đa bằng tổng thanh toán. Tiền thừa tách riêng, không cộng vào thu. Đơn còn nợ bắt buộc chọn khách hàng thực. Ngày bán lưu thành phần ngày theo quy ước nguồn. Sau khi lưu thành công xóa bản nháp và hiển thị mã hóa đơn. Cỡ nhãn và giá trị tiền trong khối thanh toán đã thống nhất (nhãn 14, giá trị 16; tổng chỉ nổi bật bằng màu).

MongoDB local đang standalone nên quy trình dùng nhật ký GiaoDichBanHang và mã yêu cầu 24 ký tự duy nhất, không giả định có transaction nhiều collection. Trước khi ghi chứng từ, giữ xe bằng CAS và giữ/trừ lượng phụ tùng bằng cập nhật nguyên tử có dấu theo mã yêu cầu. Thiếu hàng/dịch vụ trước giai đoạn ghi thì hoàn trả phần đã giữ; sau khi bắt đầu ghi chứng từ thì tiếp tục hoàn tất, không xóa bù chứng từ đã ghi. Các phép ghi quan trọng dùng journaled write concern. Chứng từ có TrangThaiLuu=dang_luu được ẩn khỏi lịch sử khách hàng; chỉ hoàn tất khi chứng từ, công nợ, khoản thu và tồn kho đã cập nhật đủ. Đây là quy trình phục hồi, không phải transaction nguyên tử tức thời trên nhiều collection.

Thử lại dùng chính mã yêu cầu và nội dung bất biến; đơn đã hoàn tất trả đúng mã cũ và không trừ tồn/thu tiền lần hai. Nếu mất xác nhận, giữ nguyên/khóa bản nháp và cho thử lại, đồng thời tự thử xác nhận lại. Khi mở dashboard, ứng dụng tìm nhật ký chưa hoàn tất để phục hồi; khóa tiến trình hết hạn sau 60 giây, có thử lại định kỳ. Nhật ký hủy và hoàn tất giữ lại để kiểm tra. Các collection chưa có màn hình hiện tại nếu thêm màn hình tài chính phải lọc/join HoaDonBan.TrangThaiLuu, tránh hiển thị các bản chiếu chưa hoàn tất. Dòng giữ hàng không được thêm vào đơn khác; xóa khách hàng cũng kiểm tra giữ chỗ của đơn đang lưu.

Quy trình schema `../upgrade_sales_schema.py` mặc định chỉ kiểm tra; --apply tự sao lưu rồi thay validator/index, kiểm tra mã định danh trùng và xác nhận hash các chứng từ cũ không thay đổi. Sao lưu thực tế: `../sales-schema-backup-20261104-122824/XM-before-sales-v3.archive.gz`; báo cáo cùng thư mục. `../test_upgrade_sales_schema.py` thử validator trong database riêng. `tool/check_sales.dart` kiểm tra đơn hỗn hợp, giảm giá, tiền thừa, thu đúng số thực, công nợ, tồn, lưu lặp, cạnh tranh cùng xe, hoàn trả khi lỗi và phục hồi gián đoạn/mất xác nhận trong database thử riêng rồi dọn database thử. Không tạo hóa đơn mẫu trong XM.


### Ngày công nợ khi tạo đơn

Đã kiểm tra HoaDonBan, SoNo và TraNo: ngày hẹn/ngày tính lãi thuộc đầu đơn HoaDonBan; SoNo giữ số tiền đã trả/còn nợ và liên kết IdHoaDon, không lưu trùng ngày ở SoNo. Khi khách còn nợ, khu vực thanh toán hiện Ngày hẹn thanh toán và Ngày tính lãi, cả hai bắt buộc và không trước ngày bán. Ngày tính lãi độc lập với ngày hẹn, không tự đặt lịch hoặc tự tính lãi suất. Khi thanh toán hết, vẫn hiển thị hai trường nhưng vô hiệu hóa; bản lưu đơn trả hết mới có hai giá trị null. Đã bỏ nút Thanh toán đủ, nhập trực tiếp số tiền khách thanh toán.

SalesController giữ các ngày khi chuyển tab; bản nháp bất biến trong nhật ký có NgayHen/NgayTinhLai và PhienBanNgayCongNo=1. Các ngày được truyền vào xem trước, lưu đúng vào HoaDonBan và giữ nguyên khi phục hồi đơn gián đoạn. Đơn cũ/nhật ký trước phiên bản ngày công nợ vẫn giữ nội dung ban đầu, không tự điền ngày giả hoặc sửa các bất thường lịch sử.

Database có marker sales_debt_dates_v1, ràng buộc thêm ngày cho các đầu đơn mới có PhienBanNgayCongNo=1; source cũ không bị áp điều kiện thứ tự ngày mới. Quy trình ../upgrade_sale_debt_dates.py mặc định kiểm tra, --apply sao lưu và kiểm tra hash trước/sau. Sao lưu thực tế: ../sales-debt-dates-backup-20261104-124206/XM-before-debt-dates.archive.gz. Đã thử validator và chống mất ngày khi phục hồi trong database riêng; không tạo đơn mẫu trong XM.

Ngày hẹn thanh toán/ngày tính lãi hiển thị cùng các ô giảm giá và khách thanh toán ở khối dưới cùng; đã bỏ tiêu đề Thanh toán của khối, giữ điều kiện hiện trường và kiểm tra ngày trước khi lưu.

Các ô Giảm giá, Khách thanh toán, Ngày hẹn thanh toán, Ngày tính lãi được xếp trên một hàng, nhãn/ô nhập thẳng hàng. Cửa sổ quá hẹp cuộn ngang hàng ô nhập để vẫn giữ độ rộng dễ đọc. Nút Xem trước đơn hàng và Lưu đơn hàng căn sát phải khối thanh toán.

Style ô nhập dùng chung InputDecorationTheme: label luôn nổi trên viền kể cả ô trống, nền trắng, bo góc 10; viền tập trung màu xanh và lỗi màu đỏ. Bốn ô thanh toán dùng labelText cùng theme, đã bỏ nhãn rời bên ngoài để thẳng hàng và cùng style với các form còn lại. Các thanh tìm kiếm dùng hint tiếp tục giữ chiều cao và nút thêm đã căn chỉnh.

Hai khu vực Khách hàng / Thông tin đơn hàng trong view bán hàng dùng nhãn đặt trên viền, chiều cao cố định theo kích thước cửa sổ/cỡ chữ. Dòng thông tin khách hàng được dành chỗ trước nên chọn hoặc thêm khách không làm thay đổi chiều cao hay vị trí danh sách. Bốn ô thanh toán luôn hiển thị; ô ngày hẹn/ngày tính lãi bị disable khi không còn nợ, giữ giá trị bản nháp nếu đổi lại sang còn nợ. Quy tắc lưu vẫn bỏ ngày trên đơn mới trả hết.

Đã tăng khoảng cách giữa tab Bán hàng và hai khối thông tin đầu đơn lên 24 px. Khối khách hàng dành sẵn hai dòng cho mã/điện thoại và địa chỉ, nên chọn/thêm/đổi khách vẫn giữ nguyên chiều cao. Danh sách gợi ý trả DiaChiHienThi ghép địa chỉ chi tiết và tên xã nguồn; khách thêm mới dùng địa chỉ nhập nguyên văn. Địa chỉ dài rút gọn trong dòng và có tooltip để xem đầy đủ.

## Đối chiếu form thêm sản phẩm vào lô

Đã đọc schema/metadata thực tế của NhapHang, Xe, XeMoi, XeCu, SanPham, TonKhoPhuTung và HangXe. Form xe thêm Hãng xe (chọn theo danh mục), Giá bán; xe mới thêm Tiền đăng ký cùng số khung/số máy/biển số. Xe cũ dùng biển số và Ghi chú xe theo XeCu; không hiện các trường số khung/số máy không có trong cấu trúc nguồn XeCu. Phụ tùng có Mã sản phẩm, Đơn vị tính, Số lượng, Giá nhập và Giá bán tham khảo. Trường nguồn nullable để trống vẫn là null, không tự coi là 0; giá tiền phải không âm.

Mã lô đã mở được giữ trong ReceiptPreview.batchId và trường XeMoi.IdNhapHang. Ngày/đối tác của lô được kế thừa, không yêu cầu nhập lại. Xe nhập có một chiếc mỗi bản ghi và trạng thái Chưa bán (Xe.TinhTrang=true) theo quy ước đã đối chiếu hóa đơn; mã legacy XeMoi.TrangThai chỉ thấy 0/null nên không gán nhãn nghiệp vụ hoặc tự chọn 0. Tiền đăng ký là trường riêng, không tự cộng vào GiaNhap/tổng tiền lô. IdXe/IdSanPham sẽ do lớp lưu cấp, không cho nhập tay.

ReceiptLine có ánh xạ tách biệt toVehicleFields, toVehicleDetailFields, toCatalogFields, toPartStockFields; bản xem trước giữ đầy đủ dữ liệu bổ sung. Các ánh xạ tạo mới không được dùng như lệnh ghi đè catalog/tồn kho hiện hữu. Dữ liệu gốc chỉ có liên kết lô xe mới qua XeMoi.IdNhapHang; không tự suy diễn chi tiết lô xe cũ/phụ tùng. Luồng nhập vẫn là bản nháp/xem trước, chưa ghi sản phẩm hoặc phiếu nhập vào MongoDB. Đã kiểm thử mapping, giá null/0/âm, hãng tải lỗi/thử lại và popup thêm vào đúng lô; kiểm tra lần này không thay đổi dữ liệu XM.


### MongoDB Cloud

Cài đặt → MongoDB Cloud: nhập URI `mongodb+srv://.../XM`, kiểm tra và lưu kết nối.
Cho phép IP máy truy cập trên Atlas; tài khoản cần quyền đọc, ghi, tạo collection,
chỉ mục và tạo database bản sao. Chuỗi kết nối được lưu cùng cấu hình kết nối trong
kho bảo mật của hệ điều hành.

- So sánh phiên bản: tính mã SHA-256 từ nội dung, chỉ mục và validator; lưu phiên bản,
  số lần thay đổi quan sát được và thời gian kiểm tra trong `_app_sync_meta` trên
  mỗi database, đồng thời lưu phiên bản gần nhất trong cấu hình ứng dụng.
- Đồng bộ lên cloud / tải về: luôn so sánh trước, hiện số bản ghi chỉ có ở từng bên,
  giống nhau, xung đột nội dung và xung đột cấu trúc. Gộp theo `_id` vào database mới.
- Khi xung đột, mặc định không ghi đè. Người dùng phải chọn ưu tiên máy hoặc cloud.
  Bản ghi chỉ có ở một bên được giữ lại; không tự truyền thao tác xóa. Bộ đếm cấp mã
  giữ giá trị lớn nhất. Các chỉ mục duy nhất và validator được kiểm tra khi tạo bản gộp.
- Phiên bản thay đổi sau khi xác nhận hoặc trong khi gộp sẽ làm thao tác dừng;
  phải so sánh lại. Bản gốc không bị ghi đè và kết quả chưa hoàn tất không được chọn.

Sau khi gộp, kết quả được tạo ở cả hai phía và đối chiếu toàn bộ nội dung/chỉ mục.
Ứng dụng chuyển cả URI máy và URI cloud sang hai bản đã đối chiếu, dùng chung mã
phiên bản và số phiên bản; các database gốc được giữ lại. Đây là gộp hai bản dữ liệu theo khóa và bên ưu tiên,
không phải gộp ba chiều hoặc tự giải quyết quan hệ hóa đơn/công nợ/tồn kho. Cần dừng
nhập liệu và đối chiếu nghiệp vụ trước khi ưu tiên một bên. Tài khoản cloud cần quyền
ghi metadata, tạo database, collection và index; view/time series chưa được hỗ trợ.

Chỉ phát hành/đẩy GitHub khi được yêu cầu; các thay đổi đang phát triển được giữ ở máy.


### Nhắc đồng bộ và lịch sử

Mỗi lần mở app, nếu đã đủ 30 ngày từ lần đồng bộ thành công gần nhất thì hiện lời
nhắc, có nút mở thẳng tab MongoDB Cloud hoặc để sau. Nếu chưa từng đồng bộ, mốc
bắt đầu được lưu từ lần đầu dùng cơ chế này. Lỗi hoặc hủy thao tác không lùi mốc nhắc.

Tab Cloud chia thành Kết nối, Phiên bản & đồng bộ, Lịch sử. Cấu hình bảo mật lưu
thời điểm thành công gần nhất và 50 lần thực hiện gần nhất trên máy (thành công/
thất bại, chiều đồng bộ, phiên bản, số bảng/dòng), không lưu URI/mật khẩu trong lịch sử.


### Kiểm thử đồng bộ với MongoDB thật

`tool/test_cloud_sync_live.py` đọc hai kết nối đã lưu trong Keychain trên macOS
(hoặc biến môi trường `XEMAY_LOCAL_URI`, `XEMAY_CLOUD_URI`), tạo database thử nghiệm
riêng với sản phẩm/khách hàng mẫu, thử tải lên rồi thay đổi dữ liệu cloud và tải về.
Kiểm tra BSON, chỉ mục, validator và phiên bản hai phía; dọn đúng các database thử
nghiệm sau khi chạy. Không thay đổi cấu hình, ngày đồng bộ hay dữ liệu kinh doanh.
Báo cáo không chứa mật khẩu nằm ở `build/test-results/cloud-sync-live.json`.
Tên database bản sao giới hạn tối đa 36 byte để phù hợp giới hạn Atlas 38 byte.


### Tối ưu so sánh phiên bản cloud

So sánh đọc hai endpoint song song, đọc theo batch 5.000 dòng và chỉ giữ mã băm
bản ghi thay vì toàn bộ nội dung. Giao diện nhận tiến trình theo bảng và số dòng,
hiển thị thời gian đã chạy. Toàn bộ bước so sánh có giới hạn khoảng 3 phút.

Trên máy chủ hỗ trợ Change Streams cùng sự kiện thay đổi cấu trúc mở rộng, ứng dụng
lưu mốc xác nhận trong metadata và chỉ dùng lại phiên bản cũ nếu máy chủ xác nhận
không có thay đổi dữ liệu/chỉ mục/validator kể từ mốc đó. Nếu hai phiên bản khớp,
không tải lại dữ liệu cloud. Nếu có thay đổi, mốc hết hạn hoặc không đủ quyền theo
dõi, ứng dụng đọc và đối chiếu lại; máy standalone vẫn dùng hai lượt xác nhận.
Không suy luận dữ liệu giống nhau chỉ dựa trên số lượng bản ghi hoặc thời gian.

Đo thời gian với kết nối đã lưu: `tool/benchmark_cloud_comparison.py`.
Báo cáo tại `build/test-results/cloud-comparison-benchmark.json` (không chứa URI hoặc
mật khẩu). Việc đo chỉ đọc dữ liệu kinh doanh và cập nhật metadata phiên bản.


### Kiểm tra tương thích Windows

Mục tiêu bộ cài: Windows 10/11 x64; Windows 11 ARM chạy ứng dụng x64 qua giả lập.
Không phát hành bản Windows 32-bit hoặc Windows 10 ARM. Python và driver SQL được
đóng gói trong bộ cài; máy sử dụng không cần cài Python riêng. Chuỗi kết nối được
bảo vệ bằng DPAPI của tài khoản Windows, log nằm dưới `%APPDATA%`.

Quy trình `tool/build_windows_installer.ps1` dựng native helper trên Windows,
kiểm tra SQL/cloud/đường dẫn có dấu và BOM, thử lại helper từ ZIP đã giải nén, xác
nhận asset nhúng đúng checksum và đủ DLL Visual C++ trước khi tạo bộ cài.
Bản Windows chỉ chứa asset helper Windows; pubspec gốc được khôi phục sau khi dựng.
Các file `run.command`, `tool/release.command`, `ensure_database_helper.py` phục vụ
máy macOS phát triển; chúng không nằm trong luồng chạy của bộ cài Windows.

Các script QA cũ `tool/check_*.dart` dùng môi trường Python/đường dẫn cố định của máy
phát triển macOS; không phải thành phần phân phối cho người dùng Windows.

### In hợp đồng cầm đồ

Khi tạo phiếu, chọn **Lưu & in hợp đồng** để lưu phiếu rồi mở thông tin bản in.
Có thể in lại bằng nút **In hợp đồng** trong chi tiết phiếu. Điền bổ sung CMND/CCCD,
ngày/nơi cấp và người ủy quyền nếu cần, sau đó chọn **Xem trước & in**. Nút **Lưu PDF**
ở góc màn hình xem trước cho phép lưu file; nút máy in mở hộp thoại in của hệ điều hành.

Nội dung lấy từ mẫu hợp đồng Toàn Hợp được cung cấp, lưu trong
`assets/templates/pawn_contract.json`; ngày tháng và số tiền bằng chữ tự điền theo
phiếu đã lưu. Mục chưa có dữ liệu để dòng chấm, không tự tạo thông tin cá nhân.
Thông tin bổ sung chỉ dùng trong lần in hiện tại, không ghi vào hồ sơ khách hàng.
Phông Noto Serif tiếng Việt đi kèm ứng dụng, không cần tải phông khi in. In hoặc lưu
PDF lỗi không tạo lại phiếu và không xóa phiếu đã lưu.

### Địa chỉ khách hàng không dùng danh mục xã

`KhachHang.DiaChiChiTiet` lưu toàn bộ địa chỉ. Khi mở phần khách hàng, phiếu
cầm đồ, đơn hàng hoặc báo cáo, ứng dụng chuyển dữ liệu cũ bằng cách ghép `Xa.TenXa`
vào địa chỉ chi tiết, bỏ `IdXa` và xóa collection `Xa` sau khi kiểm tra xong.
Danh mục cũ được lưu trong `_app_address_archive` để tra cứu khi cần. Nếu một
khách hàng tham chiếu xã không tồn tại, bước chuyển dừng và giữ nguyên dữ liệu.
Không ghép lại xã đã có ở cuối địa chỉ.

Công cụ sao chép SQL cũng xuất địa chỉ đầy đủ; đồng bộ cloud chuyển cấu trúc
trên bản gộp mới trước khi tạo hai bản dữ liệu khớp nhau. Các database nguồn
của lần đồng bộ vẫn được giữ nguyên.

### Sửa, xóa phiếu cầm đồ và hiển thị lợi nhuận

Tab Thông tin của chi tiết cầm đồ có các nút In hợp đồng, Cập nhật thông tin và
Xóa phiếu. Xóa yêu cầu xác nhận và xóa cả lịch sử thu gốc/lãi liên quan. Thay đổi
được ghi theo kế hoạch có thể tiếp tục sau lỗi, kèm bản lưu dữ liệu cũ. Tiền vay
không được thấp hơn gốc đã thu; phiếu đã thanh toán giữ nguyên khách hàng, ngày vay
và cách tính lãi để không thay đổi ý nghĩa các khoản thu trước đó.

Báo cáo bán hàng hiển thị lợi nhuận ngay phía trên danh sách. Nếu thiếu dữ liệu,
báo cáo tổng quan và bán hàng hiển thị lợi nhuận đã xác định và số đơn chưa đủ dữ
liệu, không coi giá vốn thiếu là 0. Giá nhập xe có thể lấy từ chi tiết phiếu nhập
liên kết duy nhất khi dòng bán và hồ sơ xe chưa ghi giá nhập.

### In hóa đơn từ xem trước đơn bán hàng

Trong **Xem trước đơn hàng**, chọn **In hóa đơn bán hàng** để xem/in bản nháp hoặc
**Lưu & in hóa đơn** để ghi nhận đơn và in hóa đơn có mã đơn thực tế. Bản in gồm
thông tin cửa hàng Toàn Hợp rút gọn, khách hàng và địa chỉ đầy đủ, danh sách hàng
hóa/dịch vụ, số lượng, đơn giá, thành tiền, giảm giá, thanh toán, tiền thừa và dư nợ.
Xe có số khung, số máy, biển số sẽ in kèm thông tin đó. Có thể lưu PDF từ màn hình
xem trước bản in. Đơn nhiều mặt hàng tự chia trang và lặp tiêu đề bảng.

Nếu lỗi tạo bản in sau khi đã lưu, nút In lại dùng mã đơn đã nhận, không lưu đơn
lần nữa. **In hợp đồng mua bán** tạm khóa và ghi rõ chờ mẫu hợp đồng được cung cấp.
