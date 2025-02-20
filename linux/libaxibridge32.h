#ifndef LIBAXIBRIDGE32_H
#define LIBAXIBRIDGE32_H

// so amazingly dumb

struct axi_bridge_t {
  int fd;
  unsigned int *vptr;
  unsigned int length;
};

struct axi_bridge_t *libaxibridge32_open(off_t base,
					 unsigned int size);
void libaxibridge32_close(struct axi_bridge_t *h);

void libaxibridge32_write(struct axi_bridge_t *h,
			  unsigned int addr,
			  unsigned int value);

unsigned int libaxibridge32_read(struct axi_bridge_t *h,
				 unsigned int addr);

#endif
