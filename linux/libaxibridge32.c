/*
 * This is the absolute sleaziest method of easily accessing
 * unknown IP registers inside Python.
 *
 * You might _think_ you can use mmap and /dev/mem.
 * You would be wrong - for some reason, Python ends up doing
 * multiple accesses whether you use mmap.read() or the
 * __getitem__ functionality. I have no idea why.
 *
 * So instead, we wrap it in this crappy library and ctypes
 * it in. Fun times.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#include "libaxibridge32.h"

struct axi_bridge_t current_device = { .fd = -1 };

struct axi_bridge_t *libaxibridge32_open(off_t base,
					 unsigned int size) {
  int fd;
  unsigned int *vptr;
  
  if (current_device.fd == -1) {
    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd == -1) {
      fprintf(stderr, "could not open /dev/mem\n");
      return NULL;
    }
    vptr = (unsigned int *) mmap(NULL,
				 size,
				 PROT_READ|PROT_WRITE,
				 MAP_SHARED,
				 fd,
				 base);
    if (vptr == MAP_FAILED) {
      fprintf(stderr, "could not mmap /dev/mem\n");
      close(fd);
      return NULL;
    }
    current_device.fd = fd;
    current_device.vptr = vptr;
    current_device.length = size;
  }
  return &current_device;
}

void libaxibridge32_close(struct axi_bridge_t *h) {
  if (h == NULL) return;
  munmap(h->vptr, h->length);
  close(h->fd);
  h->fd = -1;
}

// yeah, there's no safety whatsoever here, you can full-on blow $#!+
// up. just don't.
void libaxibridge32_write(struct axi_bridge_t *h,
			  unsigned int addr,
			  unsigned int value) {
  // vptr is a u32 *, so we downshift the addr by 2
  // b/c it's a byte addr to make a u32 index
  h->vptr[addr>>2] = value;
}

unsigned int libaxibridge32_read(struct axi_bridge_t *h,
				 unsigned int addr) {
  // vptr is a u32 *, so we downshift the addr by 2
  // b/c it's a byte addr to make a u32 index
  return h->vptr[addr>>2];
}
