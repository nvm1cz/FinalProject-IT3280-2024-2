.data
	MONITOR_SCREEN: .space 64             # 16 ô màn hình (4x4), mỗi ô 4 byte
color_array:
    	.word 0x00FF0000, 0x00FF0000     # RED
    	.word 0x0000FF00, 0x0000FF00     # GREEN
    	.word 0x000000FF, 0x000000FF     # BLUE
    	.word 0x00FFFFFF, 0x00FFFFFF     # WHITE
    	.word 0x00FFFF00, 0x00FFFF00     # YELLOW
   	.word 0x00FFC0CB, 0x00FFC0CB     # PINK
    	.word 0x00FFA500, 0x00FFA500     # ORANGE
    	.word 0x00800080, 0x00800080     # PURPLE

    	.align 2
key_map:                              # ánh xạ keypad vào MONITOR_SCREEN (0..15)
    	.byte 0x11, 0x21, 0x41, 0x81
    	.byte 0x12, 0x22, 0x42, 0x82
    	.byte 0x14, 0x24, 0x44, 0x84
    	.byte 0x18, 0x28, 0x48, 0x88
initial_key_map:
    	.byte 0x11, 0x21, 0x41, 0x81
    	.byte 0x12, 0x22, 0x42, 0x82
    	.byte 0x14, 0x24, 0x44, 0x84
    	.byte 0x18, 0x28, 0x48, 0x88


.eqv IN_ADDRESS_HEXA_KEYBOARD  0xFFFF0012
.eqv OUT_ADDRESS_HEXA_KEYBOARD 0xFFFF0014

	used_flags:   .space 64               # Đánh dấu đã tô (4 byte mỗi ô)
	saved_colors: .space 64               # Lưu màu đã tô vào từng ô
	match_count: .word 0     # Đếm số cặp đã ghép đúng

# Dùng để lưu trạng thái khi chọn ô đầu tiên
	first_index:  .word -1        # -1 nghĩa là chưa có ô đầu tiên
	first_color:  .word 0
	matched_flags: .space 64    # 16 x 4 bytes → 1: đã khớp, 0: chưa

.text
.globl main
main:
    la t0, color_array        # t0 trỏ đến mảng màu
    li t1, 16                 # số ô cần tô
    li t4, 0                  # số ô đã tô

fill_random_loop:
    beq t4, t1, paint_black

choose_slot:
    li a0, 16
    jal rand_mod
    mv t5, a0                 # t5 = chỉ số rand từ 0..15

    la t6, used_flags
    slli s0, t5, 2
    add t6, t6, s0
    lw s1, 0(t6)
    bnez s1, choose_slot      # nếu ô đã dùng thì chọn lại

    la s0, color_array
    slli t2, t4, 2
    add s0, s0, t2
    lw t3, 0(s0)              # t3 = màu

    la s2, MONITOR_SCREEN
    slli t5, t5, 2
    add s2, s2, t5
    sw t3, 0(s2)

    la s3, saved_colors
    add s3, s3, t5
    sw t3, 0(s3)

    li s1, 1
    sw s1, 0(t6)

    addi t4, t4, 1
    j fill_random_loop

paint_black:
    li t1, 16
    la t0, MONITOR_SCREEN
    li t2, 0x00000000         # màu đen

paint_loop:
    beqz t1, setup_interrupt
    sw t2, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    j paint_loop

# --- Cấu hình ngắt ---
setup_interrupt:
    la t0, handler
    csrrw zero, utvec, t0         # set handler address
    la s6, key_map                # lưu key_map vào s6 nếu cần

    li t1, 0x100
    csrrs zero, uie, t1           # enable external interrupt (UEIE)
    csrrsi zero, ustatus, 1       # enable interrupt (UIE) in ustatus

    li t1, IN_ADDRESS_HEXA_KEYBOARD
    li t3, 0x80
    sb t3, 0(t1)                  # bật ngắt keypad

# --- Vòng lặp chính ---
loop:
    nop
    j loop

# --- Hàm sinh số ngẫu nhiên trong [0..a0-1] ---
rand_mod:
    mv a1, a0
    li a7, 42
    ecall
    ret

# --- Trình phục vụ ngắt ---
handler:
    # s0: MONITOR_SCREEN base
    li s1, 0
    li s2, 16
    la s0, MONITOR_SCREEN          # địa chỉ base của MONITOR_SCREEN

# Kiểm tra từng hàng keypad
get_key_code:
# Quét hàng 4
    li t1, IN_ADDRESS_HEXA_KEYBOARD
    li t2, 0x88
    sb t2, 0(t1)
    li t1, OUT_ADDRESS_HEXA_KEYBOARD
    lb a0, 0(t1)
    bnez a0, front_layer

# Quét hàng 3
    li t1, IN_ADDRESS_HEXA_KEYBOARD
    li t2, 0x84
    sb t2, 0(t1)
    li t1, OUT_ADDRESS_HEXA_KEYBOARD
    lb a0, 0(t1)
    bnez a0, front_layer

# Quét hàng 2
    li t1, IN_ADDRESS_HEXA_KEYBOARDS
    li t2, 0x82
    sb t2, 0(t1)
    li t1, OUT_ADDRESS_HEXA_KEYBOARD
    lb a0, 0(t1)
    bnez a0, front_layer

# Quét hàng 1
    li t1, IN_ADDRESS_HEXA_KEYBOARD
    li t2, 0x81
    sb t2, 0(t1)
    li t1, OUT_ADDRESS_HEXA_KEYBOARD
    lb a0, 0(t1)
    bnez a0, front_layer
    uret 	# Không có nút nào được nhấn thì quay lại

# Xử lý khi có phím nhấn
# Tô màu đã lưu vào ô tương ứng
front_layer:
    mv t4, s6              # t4 = địa chỉ key_map
    li t5, 16
    li t6, 0               # index = 0

find_index:
    lb s5, 0(t4)
    beq s5, a0, found
    addi t4, t4, 1
    addi t6, t6, 1
    blt t6, t5, find_index
    uret                  # Không tìm thấy → thoát

found:
    slli t6, t6, 2                  # index * 4
    mv s7, t6
    la t0, saved_colors
    add t0, t0, t6
    lw t1, 0(t0)                    # t1 = màu tại index

    la s5, MONITOR_SCREEN
    add s5, s5, t6
    sw t1, 0(s5)                    # tô màu lên màn hình

    # Xử lý logic chọn 2 ô
    la t2, first_index
    lw t3, 0(t2)
    li t4, -1
    beq t3, t4, save_first_click    # nếu chưa có ô đầu tiên

# ---- Đây là ô thứ 2 ----
    la t5, first_color
    lw t6, 0(t5)                   # t6 = color1
    beq t6, t1, match              # nếu color1 == color2 → giữ nguyên
    
# DELAY
    li s9, 300000
    delay:
    addi s9, s9, -1
    bnez s9, delay


# ---- Không khớp → tô đen cả 2 ----
   slli t3, t3, 2                 # t3 = first_index * 4
   la s7, MONITOR_SCREEN
   add s7, s7, t3
   li s8, 0x00000000
   sw s8, 0(s7)                   # tô đen ô đầu tiên
   sw s8, 0(s5)                   # tô đen ô thứ hai
   
# ---- Phục hồi key_map[first_index] từ s10 ----
   srli t3, t3, 2                 # t3 lại về index
   la t0, key_map
   add t1, t0, t3
   sb s10, 0(t1)                  # khôi phục key_map[first_index]

# ---- Reset first_index ----
reset:
    la t2, first_index
    li t4, -1
    sw t4, 0(t2)
    uret

# ---- Lưu ô đầu tiên đã chọn ----
save_first_click:
    la t5, first_color
    sw t1, 0(t5)             # first_color = màu hiện tại

    la t2, first_index
    srli t6, t6, 2           # t6 = index (đã nhân 4 trước đó → chia lại)
    sw t6, 0(t2)             # first_index = index
    
    # Lưu giá trị key_map[first_index] vào s10 và đổi thành -1
    la t3, key_map
    add t4, t3, t6           # t4 = &key_map[first_index]
    lb s10, 0(t4)            # s10 = key_map[first_index]
    li t5, -1
    sb t5, 0(t4)             # key_map[first_index] = -1
    uret


# ---- 2 ô trùng màu ----
match:

# Tăng match_count
    la t0, match_count
    lw t1, 0(t0)
    addi t1, t1, 1
    sw t1, 0(t0)

    li t2, 8
    beq t1, t2, restart_game

# first_index = t3 
    srli s7, s7, 2         # lấy lại chỉ số ô thứ 2 (vì trước đó đã nhân 4)

    # key_map[first_index] = -1
    la t0, key_map
    add t1, t0, t3
    li t2, -1
    sb t2, 0(t1)

    # key_map[t6] = -1
    add t1, t0, s7
    sb t2, 0(t1)
    j reset

restart_game:
# Delay chút cho người chơi thấy kết quả cuối
    li t3, 100000
delay_restart:
    addi t3, t3, -1
    bnez t3, delay_restart

# Reset các biến
    la t0, match_count
    sw zero, 0(t0)

    la t0, first_index
    li t1, -1
    sw t1, 0(t0)

    la t0, first_color
    sw zero, 0(t0)
    
# Xoá used_flags
    la t0, used_flags
    li t1, 16
reset_used_flags:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, reset_used_flags

# Reset key_map 
    la t0, key_map
    li t1, 0
reset_key_map:
    la t0, initial_key_map
    la t1, key_map
    li t2, 16
copy_loop:
    lb t3, 0(t0)
    sb t3, 0(t1)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    bnez t2, copy_loop
    
restart_game_done:
    j main     # Gọi lại chương trình từ đầu



